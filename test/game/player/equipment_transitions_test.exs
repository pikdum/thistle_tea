defmodule ThistleTea.Game.Player.EquipmentTransitionsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Inventory
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
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
        Message.CmsgUseItem.handle(
          %Message.CmsgUseItem{bag: 255, slot: 12, targets: <<0::little-size(16)>>},
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
      template = %ItemTemplate{entry: item.object.entry, class: 2, subclass: 14, inventory_type: 13}
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
      equipped = Inventory.auto_equip(state, {255, 23})
      assert equipped.character.player.mainhand == weapon.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellCooldown{cooldowns: [{6119, 0}]}}}
      assert Inventory.swap(equipped, {255, 24}, {255, 15}) == equipped
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 39}}}
      assert ItemStore.get(other.object.guid) == other
    end
  end

  describe "InventoryUpdate.apply/2" do
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
end
