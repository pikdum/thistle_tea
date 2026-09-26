defmodule ThistleTea.Game.Player.WeaponProcsTest do
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
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.WeaponProcs
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  @entry 998_420
  @innate 998_421
  @enchant_spell 998_422
  @enchant 998_423

  setup [:equipment]

  describe "trigger/4" do
    test "innate and enchantment procs share one hit and spend one charge", context do
      character = WeaponProcs.trigger(context.character, context.hit, Time.now(), fn -> 0 end)
      assert Enum.map(character.internal.events, & &1.spell_id) == [@innate, @enchant_spell]
      assert Enum.all?(character.internal.events, &(&1.cast_item_guid == context.item.object.guid))
      assert charges(context.item) == 1

      character = WeaponProcs.trigger(character, context.hit, Time.now(), fn -> 0 end)
      assert Enum.map(character.internal.events, & &1.spell_id) == [@innate, @enchant_spell, @innate, @enchant_spell]
      assert Item.temporary_enchantment(ItemStore.get(context.item.object.guid)) == nil

      character = WeaponProcs.trigger(character, context.hit, Time.now(), fn -> 0 end)

      assert Enum.map(character.internal.events, & &1.spell_id) == [
               @innate,
               @enchant_spell,
               @innate,
               @enchant_spell,
               @innate
             ]
    end

    test "equipment usability and live combatants are checked when feedback arrives", context do
      %{character: character, hit: hit} = context
      bagged = %{character | player: %{character.player | mainhand: nil, inv1: context.item.object.guid}}
      broken = %{character | player: %{character.player | broken_equipment: [:mainhand]}}
      disarm = %Spell{id: 676, duration_ms: 10_000, effects: [%Effect{type: :apply_aura, aura: :mod_disarm}]}
      {disarmed, _events} = Aura.apply_spell(character, hit.target_guid, 60, disarm, Time.now())
      feral = %{character | unit: %{character.unit | class: 11, shapeshift_form: 1}}
      dead = %{character | unit: %{character.unit | health: 0}}

      for invalid <- [bagged, broken, disarmed, feral, dead] do
        assert WeaponProcs.trigger(invalid, hit, Time.now(), fn -> 0 end) == invalid
      end

      for invalid <- [%{hit | hand: :offhand}, %{hit | source_guid: 0}, %{hit | target_guid: character.object.guid}] do
        assert WeaponProcs.trigger(character, invalid, Time.now(), fn -> 0 end) == character
      end

      Metadata.update(hit.target_guid, %{alive?: false})
      assert WeaponProcs.trigger(character, hit, Time.now(), fn -> 0 end) == character
      Metadata.delete(hit.target_guid)
      assert WeaponProcs.trigger(character, hit, Time.now(), fn -> 0 end) == character
      Metadata.put(hit.target_guid, %{alive?: true})
      item = context.item
      ItemStore.put(%{item | item: %{item.item | durability: 0, max_durability: 100}})
      assert WeaponProcs.trigger(character, hit, Time.now(), fn -> 0 end) == character
      assert charges(item) == 2
    end

    test "offhand hits use only the current offhand weapon", context do
      %{character: character, item: item} = context
      player = Inventory.equip(%{character.player | mainhand: nil}, :offhand, item)
      unit = %{character.unit | mainhand_weapon: nil, offhand_weapon: character.unit.mainhand_weapon}
      character = %{character | player: player, unit: unit}
      assert WeaponProcs.trigger(character, context.hit, Time.now(), fn -> 0 end) == character
      result = WeaponProcs.trigger(character, %{context.hit | hand: :offhand}, Time.now(), fn -> 0 end)

      assert [%Effects.TriggerSpell{spell_id: @innate, attack_hand: :offhand}, %Effects.TriggerSpell{}] =
               result.internal.events

      assert charges(item) == 1
    end

    test "extra attack recursion stops before spending enchantment charges", context do
      :ets.insert(
        SpellLoader,
        {{:spell, @innate}, %Spell{id: @innate, proc_chance: 100, effects: [%Effect{type: :add_extra_attacks}]}}
      )

      assert WeaponProcs.trigger(context.character, %{context.hit | extra_attack?: true}, Time.now(), fn -> 0 end) ==
               context.character

      assert charges(context.item) == 2
    end
  end

  describe "hit feedback" do
    test "the victim routes one request to the attacker and ordinary attack feedback cannot proc twice", context do
      %{character: character, hit: hit} = context
      Entity.register(character.object.guid)
      target = %{character | object: %Object{guid: hit.target_guid}}
      EventSink.emit(target, hit)
      assert_received {:"$gen_cast", {:trigger_weapon_procs, ^hit}}
      refute_received {:"$gen_cast", {:trigger_weapon_procs, _}}

      state = %State{guid: character.object.guid, character: character}
      payload = %{victim_guid: hit.target_guid, outcome: :normal, hand: :mainhand, damage: 5}
      assert {:noreply, state, _} = PlayerServer.handle_cast({:attack_outcome, payload}, state)
      refute Enum.any?(state.character.internal.events, &is_struct(&1, Effects.TriggerSpell))
      assert charges(context.item) == 2
      assert {:noreply, state, _} = PlayerServer.handle_cast({:trigger_weapon_procs, hit}, state)
      assert length(state.character.internal.events) == 2
      assert charges(context.item) == 1
    end
  end

  defp charges(item), do: Item.temporary_enchantment(ItemStore.get(item.object.guid)).charges

  defp equipment(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    target = System.unique_integer([:positive, :monotonic])

    template = %ItemTemplate{
      entry: @entry,
      class: 2,
      subclass: 7,
      inventory_type: 13,
      delay: 2000,
      spellid_1: @innate,
      spelltrigger_1: 2
    }

    :ets.insert(ItemLoader, {@entry, template})
    :ets.insert(SpellLoader, {{:spell, @innate}, %Spell{id: @innate, proc_chance: 100}})
    :ets.insert(SpellLoader, {{:spell, @enchant_spell}, %Spell{id: @enchant_spell}})

    :ets.insert(
      EnchantmentLoader,
      {{:enchantment, @enchant},
       %ItemEnchantment{id: @enchant, effects: [%{type: 1, spell_id: @enchant_spell, amount: 100}]}}
    )

    :ets.insert(EnchantmentLoader, {{:proc_ppm, @enchant_spell}, 0.0})
    Metadata.put(target, %{alive?: true})

    item =
      ItemStore.create(template, owner: guid)
      |> Item.put_temporary_enchantment(@enchant, 60_000, 2, Time.now() + 60_000, :coating)
      |> ItemStore.put()

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: Inventory.equip(%Player{}, :mainhand, item),
      unit: %Unit{level: 60, health: 100, max_health: 100, base_health: 100, mainhand_weapon: template},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(ItemLoader, @entry)
      Enum.each([@innate, @enchant_spell], &:ets.delete(SpellLoader, {:spell, &1}))
      :ets.delete(EnchantmentLoader, {:enchantment, @enchant})
      :ets.delete(EnchantmentLoader, {:proc_ppm, @enchant_spell})
      Metadata.delete(target)
    end)

    %{
      character: character,
      item: item,
      hit: %Effects.TriggerWeaponProcs{source_guid: guid, target_guid: target, hand: :mainhand}
    }
  end
end
