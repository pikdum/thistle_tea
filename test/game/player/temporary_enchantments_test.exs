defmodule ThistleTea.Game.Player.TemporaryEnchantmentsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgUseItem
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Metadata

  @entry 998_301
  @coating 998_302
  @enchant 998_303
  @spell 998_304
  @permanent 998_305

  setup [:equipment]

  describe "apply_temporary/6" do
    test "commits a coating once with charges, bonuses, and the client timer", context do
      %{state: state, weapon: weapon, coating: coating, spell: spell} = context
      done = apply_coating(context)
      assert ItemStore.get(coating.object.guid).item.stack_count == 2
      assert %{id: @enchant, charges: 2} = Item.temporary_enchantment(ItemStore.get(weapon.object.guid))
      assert done.character.unit.max_health == 115
      assert CharacterStore.get(state.guid).unit.max_health == 115
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemEnchantTimeUpdate{duration_seconds: 60}}}
      assert Enchantments.apply_temporary(done, weapon.object.guid, spell, @enchant, 60_000, 99) == done
      assert ItemStore.get(coating.object.guid).item.stack_count == 2
    end

    test "rejects stale targets, dead casters, and incomplete costs atomically", context do
      %{state: state, weapon: weapon, coating: coating, spell: spell} = context
      missing_target = %{state | character: %{state.character | player: %{state.character.player | mainhand: nil}}}
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      missing_reagent = %{spell | reagents: [{@coating, 1}, {998_306, 1}]}

      for {invalid, cast_spell} <- [{missing_target, spell}, {dead, spell}, {state, missing_reagent}] do
        assert Enchantments.apply_temporary(
                 invalid,
                 weapon.object.guid,
                 cast_spell,
                 @enchant,
                 60_000,
                 coating.object.guid
               ) == invalid

        assert ItemStore.get(coating.object.guid) == coating
        assert ItemStore.get(weapon.object.guid) == weapon
      end
    end

    test "replacement resets charges and invalidates the old expiration", context do
      first = apply_coating(context)
      guid = context.weapon.object.guid
      old = Item.temporary_enchantment(ItemStore.get(guid))
      ItemStore.put(Item.spend_enchantment_charge(ItemStore.get(guid), old.token))
      second = apply_coating(%{context | state: first})
      replacement = Item.temporary_enchantment(ItemStore.get(guid))
      assert replacement.charges == 2
      refute replacement.token == old.token
      assert second.character.unit.max_health == 115
      assert Enchantments.expire(second, guid, old.token) == second
    end

    test "instant item use delegates consumption to the owner transaction", context do
      message = %CmsgUseItem{
        bag: Inventory.bag_0(),
        slot: 23,
        spell_count: 1,
        targets: TargetCodec.encode(Target.item(context.weapon.object.guid))
      }

      state = CmsgUseItem.handle(message, context.state, fn @spell -> context.spell end)
      assert ItemStore.get(context.coating.object.guid).item.stack_count == 3
      assert_receive {:enchant_item, guid, spell, @enchant, duration, source}
      assert guid == context.weapon.object.guid
      assert source == context.coating.object.guid

      assert {:noreply, done, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info({:enchant_item, guid, spell, @enchant, duration, source}, state)

      assert ItemStore.get(source).item.stack_count == 2
      assert done.character.unit.max_health == 115
    end
  end

  describe "trigger_weapon_procs/3" do
    test "only successful rolls consume charges and the final proc precedes removal", context do
      done = apply_coating(context)
      payload = %{outcome: :normal, victim_guid: 2}
      character = Enchantments.trigger_weapon_procs(done.character, payload, fn -> 0.9 end)
      assert charges(context) == 2
      character = Enchantments.trigger_weapon_procs(character, %{payload | outcome: :miss}, fn -> 0.1 end)
      assert charges(context) == 2
      character = Enchantments.trigger_weapon_procs(character, payload, fn -> 0.1 end)
      assert charges(context) == 1
      character = Enchantments.trigger_weapon_procs(character, payload, fn -> 0.1 end)
      assert Item.temporary_enchantment(ItemStore.get(context.weapon.object.guid)) == nil
      assert character.unit.max_health == 105
      assert Item.active_enchantments(ItemStore.get(context.weapon.object.guid), Time.now()) == [{0, @permanent}]
      assert length(Enum.filter(character.internal.events, &is_struct(&1, Effects.TriggerSpell))) == 2
      assert Enchantments.trigger_weapon_procs(character, payload, fn -> 0.1 end) == character
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemEnchantTimeUpdate{duration_seconds: 0}}}
    end

    test "offhand attacks and unequipped or broken weapons do not spend mainhand charges", context do
      character = apply_coating(context).character
      payload = %{outcome: :normal, victim_guid: 2, hand: :offhand}
      assert Enchantments.trigger_weapon_procs(character, payload, fn -> 0.1 end) == character
      bagged = %{character | player: %{character.player | mainhand: nil, inv2: context.weapon.object.guid}}
      assert Enchantments.trigger_weapon_procs(bagged, %{payload | hand: :mainhand}, fn -> 0.1 end) == bagged
      item = ItemStore.get(context.weapon.object.guid)
      ItemStore.put(%{item | item: %{item.item | durability: 0, max_durability: 100}})
      assert Enchantments.trigger_weapon_procs(character, %{payload | hand: :mainhand}, fn -> 0.1 end) == character
      assert charges(context) == 2
    end

    test "depletion suppresses later effects from the same enchantment snapshot", context do
      definition = EnchantmentLoader.get(@enchant)

      :ets.insert(
        EnchantmentLoader,
        {{:enchantment, @enchant},
         %{definition | effects: definition.effects ++ [%{type: 1, spell_id: 0, amount: 100}]}}
      )

      :ets.insert(EnchantmentLoader, {{:charges, @spell}, 1})
      character = apply_coating(context).character
      character = Enchantments.trigger_weapon_procs(character, %{outcome: :normal, victim_guid: 2}, fn -> 0.1 end)
      assert length(Enum.filter(character.internal.events, &is_struct(&1, Effects.TriggerSpell))) == 1
      assert Item.temporary_enchantment(ItemStore.get(context.weapon.object.guid)) == nil
    end
  end

  describe "restore/1" do
    test "death and reconnect preserve remaining charges without renewing the timer", context do
      done = apply_coating(context)
      character = Enchantments.trigger_weapon_procs(done.character, %{outcome: :normal, victim_guid: 2}, fn -> 0.1 end)
      enchantment = Item.temporary_enchantment(ItemStore.get(context.weapon.object.guid))
      dead = Core.take_damage(character, 1000, Time.now())
      assert Enchantments.trigger_weapon_procs(dead, %{outcome: :normal, victim_guid: 2}, fn -> 0.1 end) == dead
      restored = Enchantments.restore(dead)
      assert restored.unit.health == 0
      assert Item.temporary_enchantment(ItemStore.get(context.weapon.object.guid)) == enchantment
      assert enchantment.charges == 1
      assert restored.unit.max_health == 115
    end

    test "login clears expired coatings while retaining permanent bonuses", context do
      done = apply_coating(context)
      item = ItemStore.get(context.weapon.object.guid)
      ItemStore.put(Item.put_temporary_enchantment(item, @enchant, 1, 1, Time.now() - 1, :expired))
      restored = Enchantments.restore(done.character)
      assert Item.temporary_enchantment(ItemStore.get(item.object.guid)) == nil
      assert restored.unit.max_health == 105
    end
  end

  describe "EventSink.emit/3" do
    test "enchant completion uses the supplied owner context", context do
      effect = %{
        Effects.enchant_item(context.weapon.object.guid, context.spell, hd(context.spell.effects))
        | cast_item_guid: context.coating.object.guid
      }

      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn -> send(owner, :stop) end)
      EventSink.emit(context.state.character, [effect], Context.new(owner))
      refute_receive {:enchant_item, _, _, _, _, _}
      assert {:messages, [{:enchant_item, _, _, @enchant, 60_000, _}]} = Process.info(owner, :messages)
    end
  end

  defp charges(context), do: Item.temporary_enchantment(ItemStore.get(context.weapon.object.guid)).charges

  defp apply_coating(context) do
    Enchantments.apply_temporary(
      context.state,
      context.weapon.object.guid,
      context.spell,
      @enchant,
      60_000,
      context.coating.object.guid
    )
  end

  defp equipment(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    {:ok, _} = Entity.register(guid)
    template = %ItemTemplate{entry: @entry, class: 2, subclass: 15, inventory_type: 13, item_level: 1}
    :ets.insert(ItemLoader, {@entry, template})

    :ets.insert(EnchantmentLoader, [
      {{:enchantment, @enchant},
       %ItemEnchantment{
         id: @enchant,
         effects: [%{type: 1, spell_id: 0, amount: 20}, %{type: 5, spell_id: 1, amount: 10}]
       }},
      {{:enchantment, @permanent}, %ItemEnchantment{id: @permanent, effects: [%{type: 5, spell_id: 1, amount: 5}]}},
      {{:charges, @spell}, 2}
    ])

    weapon = ItemStore.create(template, owner: guid) |> Item.put_permanent_enchantment(@permanent) |> ItemStore.put()

    coating =
      ItemStore.create(%ItemTemplate{entry: @coating, stackable: 20, spellid_1: @spell, spellcharges_1: -1},
        owner: guid,
        stack_count: 3
      )

    player = Inventory.equip(%Player{inv1: coating.object.guid}, :mainhand, weapon)

    character =
      %Character{
        id: guid,
        object: %Object{guid: guid},
        player: player,
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        unit: %Unit{health: 100, max_health: 100, base_health: 100, level: 50, class: 4, race: 1, auras: []}
      }
      |> Character.sync_equipment_stats()

    spell = %Spell{
      id: @spell,
      base_level: 20,
      equipped_item_class: 2,
      effects: [%Effect{type: :enchant_item_temporary, base_points: 60, die_sides: 0, misc_value: @enchant}]
    }

    on_exit(fn ->
      Enum.each([weapon.object.guid, coating.object.guid], &ItemStore.delete/1)
      :ets.delete(ItemLoader, @entry)

      Enum.each(
        [{:enchantment, @enchant}, {:enchantment, @permanent}, {:charges, @spell}],
        &:ets.delete(EnchantmentLoader, &1)
      )

      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
    end)

    %{
      state: %State{ready: true, guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character},
      weapon: weapon,
      coating: coating,
      spell: spell
    }
  end
end
