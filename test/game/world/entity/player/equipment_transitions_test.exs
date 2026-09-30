defmodule ThistleTea.Game.World.Entity.Player.EquipmentTransitionsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Player.Inventory
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Player.UsableItems
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  setup [:equipment]

  describe "auto_equip/2" do
    test "commits and projects an equip cooldown that also rejects actual item use", %{
      state: state,
      item: item,
      spell: spell
    } do
      before = Time.now()
      equipped = Inventory.auto_equip(state, {255, 23})
      guid = item.object.guid
      id = spell.id
      assert equipped.character.player.trinket1 == guid
      assert equipped.character.player.inv1 == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{item_guid: ^guid, spell_id: ^id}}}
      assert equipped.character.internal.events == []
      assert CharacterStore.get(state.guid) == equipped.character
      assert Cooldowns.ready_at(equipped.character, spell) in (before + 30_000)..(Time.now() + 30_000)

      rejected =
        use_item(
          %Inbound.CmsgUseItem{bag: 255, slot: 12, targets: <<0::little-size(16)>>},
          equipped,
          fn ^id -> spell end
        )

      assert rejected.character.internal.casting == nil
      assert ItemStore.get(guid).item.spell_charges == item.item.spell_charges
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: ^id, reason: 0x3C}}}
    end

    test "combat rejection leaves item ownership and stored character unchanged", %{state: state, item: item} do
      state = %{state | character: %{state.character | internal: %{state.character.internal | in_combat: true}}}
      stored = CharacterStore.get(state.guid)
      assert Inventory.auto_equip(state, {255, 23}) == state
      assert ItemStore.get(item.object.guid) == item
      assert CharacterStore.get(state.guid) == stored
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 60}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
    end
  end

  describe "equip_item/3" do
    test "resolves the current bag position and swaps into the requested trinket slot", %{state: state, item: item} do
      bag =
        ItemStore.create(%ItemTemplate{entry: 900_001, class: 1, inventory_type: 18, container_slots: 4},
          owner: state.guid
        )

      previous = ItemStore.create(Item.template(item), owner: state.guid)
      on_exit(fn -> Enum.each([bag, previous], &ItemStore.delete(&1.object.guid)) end)
      ItemStore.put(%{bag | container: %{bag.container | slot_3: item.object.guid}})
      player = %{state.character.player | inv1: 0, bag1: bag.object.guid, trinket2: previous.object.guid}
      state = %{state | character: %{state.character | player: player}}

      equipped = Inventory.equip_item(state, item.object.guid, 13)

      assert equipped.character.player.trinket2 == item.object.guid
      assert equipped.character.player.trinket1 in [nil, 0]
      assert ItemStore.get(bag.object.guid).container.slot_3 == previous.object.guid
      assert CharacterStore.get(state.guid) == equipped.character
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
    end

    test "same-slot requests leave the equip cooldown and packets untouched", %{state: state, item: item, spell: spell} do
      message = %Inbound.CmsgAutoequipItemSlot{item_guid: item.object.guid, destination_slot: 13}
      equipped = Inbound.handle(message, state)
      deadline = Cooldowns.ready_at(equipped.character, spell)
      assert is_integer(deadline)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}

      assert Inbound.handle(message, equipped) == equipped
      assert Cooldowns.ready_at(CharacterStore.get(state.guid), spell) == deadline
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
    end

    test "ignores unowned items, missing items, and storage destinations", %{state: state, item: item} do
      for slot <- [-1, 23, 39, 63, 255] do
        assert Inventory.equip_item(state, item.object.guid, slot) == state
      end

      assert Inventory.equip_item(state, 0, 13) == state
      detached = put_in(state.character.player.inv1, 0)
      assert Inventory.equip_item(detached, item.object.guid, 13) == detached
      ItemStore.put(%{item | item: %{item.item | owner: state.guid + 1}})
      assert Inventory.equip_item(state, item.object.guid, 13) == state
      assert CharacterStore.get(state.guid) == state.character
      refute_received {:"$gen_cast", {:send_packet, _packet}}
    end

    test "rejects combat and incompatible destinations before committing", %{state: state, item: item} do
      combat = put_in(state.character.internal.in_combat, true)
      assert Inventory.equip_item(combat, item.object.guid, 13) == combat
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 60}}}
      assert Inventory.equip_item(state, item.object.guid, 0) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 3}}}
      assert ItemStore.get(item.object.guid) == item
      assert CharacterStore.get(state.guid) == state.character
    end

    test "equips bags into an explicit bag-bar slot", %{state: state} do
      bag =
        ItemStore.create(%ItemTemplate{entry: 900_002, class: 1, inventory_type: 18, container_slots: 4},
          owner: state.guid
        )

      on_exit(fn -> ItemStore.delete(bag.object.guid) end)
      state = put_in(state.character.player.inv2, bag.object.guid)

      equipped = Inventory.equip_item(state, bag.object.guid, 22)

      assert equipped.character.player.bag4 == bag.object.guid
      assert equipped.character.player.bag1 in [nil, 0]
      assert equipped.character.player.inv2 == 0
      assert CharacterStore.get(state.guid) == equipped.character
    end
  end

  describe "swap/3" do
    test "rejects both direct unequip and auto-store of combat trinkets", %{state: state} do
      equipped = Inventory.auto_equip(state, {255, 23})

      combat = %{
        equipped
        | character: %{equipped.character | internal: %{equipped.character.internal | in_combat: true}}
      }

      assert Inventory.swap(combat, {255, 12}, {255, 23}) == combat
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 60}}}
      assert Inventory.auto_store_in_bag(combat, {255, 12}, 255) == combat
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 60}}}
    end

    test "a combat weapon swap publishes the GCD and rejects a second swap", %{state: state, item: item} do
      template = %ItemTemplate{entry: item.object.entry, class: 2, subclass: 14, inventory_type: 13, delay: 3_400}
      :ets.insert(ItemLoader, {template.entry, template})
      on_exit(fn -> :ets.delete(ItemLoader, template.entry) end)
      weapon = Item.build(template, item.object.guid, owner: state.guid)
      ItemStore.put(weapon)
      other = ItemStore.create(%{template | entry: template.entry + 1}, owner: state.guid)
      on_exit(fn -> ItemStore.delete(other.object.guid) end)
      cache_spell(%Spell{id: 6119, gcd_category: 133, gcd_ms: 1_500})

      character = %{
        state.character
        | player: %{state.character.player | inv2: other.object.guid},
          internal: %{state.character.internal | in_combat: true}
      }

      state = %{state | character: character}
      before = Time.now()
      equipped = Inventory.auto_equip(state, {255, 23})
      assert equipped.character.player.mainhand == weapon.object.guid
      assert equipped.character.internal.blackboard.combat.next_attack_at in (before + 3_400)..(Time.now() + 3_400)
      assert equipped.character.internal.broadcast_update?
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellCooldown{cooldowns: [{6119, 0}]}}}
      assert Inventory.swap(equipped, {255, 24}, {255, 15}) == equipped
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 39}}}
      assert ItemStore.get(other.object.guid) == other
    end
  end

  describe "InventoryUpdate.apply/2" do
    test "change-set removal restarts unarmed combat without needing the deleted item", %{state: state, item: item} do
      template = %ItemTemplate{entry: item.object.entry, class: 2, inventory_type: 13, delay: 3_400}

      character = %{
        state.character
        | player: %{state.character.player | mainhand: item.object.guid, inv1: 0},
          unit: %{
            state.character.unit
            | mainhand_weapon: template,
              base_melee_attack_time: 3_400,
              base_attack_time: 3_400
          },
          internal: %{state.character.internal | in_combat: true, blackboard: Blackboard.new()}
      }

      changes = ChangeSet.new(%{character.player | mainhand: 0})
      changes = %{changes | destroyed: %{item.object.guid => item}}
      before = Time.now()
      removed = InventoryUpdate.apply(%{state | character: character}, {:ok, changes})
      assert ItemStore.get(item.object.guid) == nil
      assert removed.character.unit.mainhand_weapon == nil
      assert removed.character.internal.blackboard.combat.next_attack_at in (before + 2_000)..(Time.now() + 2_000)
    end

    test "change sets share the cooldown transition and no-op resync leaves its deadline alone", %{
      state: state,
      item: item,
      spell: spell
    } do
      player = %{state.character.player | trinket1: item.object.guid, inv1: 0}
      changes = ChangeSet.new(player)
      equipped = InventoryUpdate.apply(state, {:ok, changes})
      deadline = Cooldowns.ready_at(equipped.character, spell)
      assert is_integer(deadline)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
      synced = InventoryUpdate.apply(equipped, {:ok, changes})
      assert Cooldowns.ready_at(synced.character, spell) == deadline
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
      assert [%{spell_id: id, spell_ms: remaining}] = Cooldowns.initial(CharacterStore.get(state.guid), %{}, Time.now())
      assert id == spell.id
      assert remaining > 29_000
    end

    test "system removal can expire equipment while the owner is fighting", %{state: state} do
      equipped = Inventory.auto_equip(state, {255, 23})

      combat = %{
        equipped
        | character: %{equipped.character | internal: %{equipped.character.internal | in_combat: true}}
      }

      removed = InventoryUpdate.apply(combat, {:ok, ChangeSet.new(%{combat.character.player | trinket1: 0})})
      assert removed.character.player.trinket1 == 0
    end
  end

  describe "EventSink.emit/3" do
    test "sends the vanilla item packet only to the explicit owner", %{state: state, item: item, spell: spell} do
      effect = %Effects.ItemCooldown{item_guid: item.object.guid, spell_id: spell.id}
      EventSink.emit(state.character, effect)
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{}}}
      EventSink.emit(state.character, effect, Context.new(self()))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemCooldown{} = packet}}

      assert Message.SmsgItemCooldown.to_binary(packet) ==
               <<item.object.guid::little-size(64), spell.id::little-size(32)>>

      assert Message.SmsgItemCooldown.opcode() == 0xB0
    end
  end

  defp equipment(_context) do
    owner = System.unique_integer([:positive, :monotonic])
    id = owner + 800_000
    spell = %Spell{id: id, cast_time_ms: 10_000}
    cache_spell(spell)

    item =
      ItemStore.create(%ItemTemplate{entry: id, class: 4, inventory_type: 12, spellid_1: id, spellcharges_1: 3},
        owner: owner
      )

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      player: %Player{inv1: item.object.guid},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, class: 1, race: 1, level: 60},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(CharacterStore, owner)
      Metadata.delete(owner)
    end)

    %{state: %State{guid: owner, ready: true, character: character}, item: item, spell: spell}
  end

  defp cache_spell(spell) do
    previous = :ets.lookup(SpellLoader, {:spell, spell.id})
    :ets.insert(SpellLoader, {{:spell, spell.id}, spell})

    on_exit(fn ->
      :ets.delete(SpellLoader, {:spell, spell.id})
      :ets.insert(SpellLoader, previous)
    end)
  end

  defp use_item(%{bag: bag, slot: slot, targets: targets}, state, load_spell),
    do: UsableItems.use(state, {bag, slot}, targets, load_spell)
end
