defmodule ThistleTea.Game.Entity.Logic.EquipmentAurasTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:equipment]

  describe "sync/4" do
    test "projects skill enchant bonuses and clears them on removal", %{character: character, enchants: [entry | _]} do
      {slot, item, enchant_slot, enchantment} = entry
      enchantment = %{enchantment | effects: [%{type: 3, spell_id: 3}]}
      spell = %Spell{id: 3, effects: [%Effect{type: :apply_aura, aura: :mod_skill, misc_value: 95, base_points: 1}]}
      equipped = EquipmentAuras.sync(character, [{slot, item, enchant_slot, enchantment}], fn 3 -> spell end, 0)
      assert equipped.player.skill_bonuses == %{95 => {1, 0}}
      assert equipped.player.skills == character.player.skills
      removed = EquipmentAuras.sync(equipped, [], fn _ -> nil end, 100)
      assert removed.player.skill_bonuses == %{}
    end

    test "stacks identical enchants by source and removes only unequipped sources", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      both = EquipmentAuras.sync(character, enchants, get_spell, 0)
      assert both.unit.max_health == 110
      assert both.unit.health == 100
      assert length(both.unit.auras) == 2
      assert Enum.all?(both.unit.auras, &is_nil(&1.slot))
      assert EquipmentAuras.sync(both, enchants, get_spell, 100) == both
      one = EquipmentAuras.sync(both, tl(enchants), get_spell, 200)
      assert one.unit.max_health == 105
      assert length(one.unit.auras) == 1
      removed = EquipmentAuras.sync(one, [], get_spell, 300)
      assert removed.unit.max_health == 100
      assert removed.unit.auras == []
    end

    test "retains enchant passives through death and resurrection", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      equipped = EquipmentAuras.sync(character, enchants, get_spell, 0)
      dead = Core.take_damage(equipped, 1_000, 2, now: 100)
      assert dead.unit.health == 0
      assert length(dead.unit.auras) == 2
      {restored, _events} = Death.resurrect(dead, 1.0, 200)
      assert restored.unit.health == 110
      assert restored.unit.max_health == 110
    end

    test "replacing an enchant replaces its spell source", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      [first | _] = enchants
      equipped = EquipmentAuras.sync(character, [first], get_spell, 0)
      {slot, item, enchant_slot, enchantment} = first
      new = {slot, item, enchant_slot, %{enchantment | effects: [%{type: 3, spell_id: 2}]}}
      spell = %Spell{id: 2, effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 20}]}
      replaced = EquipmentAuras.sync(equipped, [new], fn 2 -> spell end, 100)
      assert replaced.unit.max_health == 120
      assert length(replaced.unit.auras) == 1
    end
  end

  describe "sync/5" do
    test "item and enchant procs retain their item identity while sets have no casting item", %{
      character: character,
      enchants: [enchant | _]
    } do
      {slot, item, enchant_slot, definition} = enchant

      spell = %Spell{
        id: 4,
        proc_type_mask: 4,
        proc_chance: 100,
        effects: [%Effect{type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 5}]
      }

      enchant = {slot, item, enchant_slot, %{definition | effects: [%{type: 3, spell_id: 4}]}}
      sources = [{:item_equip, 99, 4}, {:item_set, 1, 4}]
      equipped = EquipmentAuras.sync(character, [enchant], fn 4 -> spell end, 0, sources)
      context = %{victim_guid: 2, outcome: :normal, proc_type: :deal_melee_swing, now: 100}
      {_equipped, events} = Aura.reactions(equipped, :melee_hit_dealt, context)
      assert Enum.map(events, & &1.cast_item_guid) == [item.object.guid, 99, nil]
    end

    test "removes outdoor set bonuses indoors and restores their source on exit", %{character: character} do
      spell = %Spell{
        id: 23_218,
        attributes: MapSet.new([:passive, :only_outdoors]),
        effects: [%Effect{type: :apply_aura, aura: :mod_speed_always, base_points: 10}]
      }

      source = {:item_set, 201, spell.id}
      lookup = fn _ -> spell end
      outside = EquipmentAuras.sync(character, [], lookup, 0, [source])
      assert Aura.has_spell?(outside, spell.id)
      inside = %{outside | internal: %{outside.internal | outdoors?: false}}
      inside = EquipmentAuras.sync(inside, [], lookup, 1000, [source])
      refute Aura.has_spell?(inside, spell.id)
      restored = %{inside | internal: %{inside.internal | outdoors?: true}}
      restored = EquipmentAuras.sync(restored, [], lookup, 2000, [source])
      assert [%{item_source: ^source}] = restored.unit.auras
      assert EquipmentAuras.sync(restored, [], lookup, 3000, [source]) == restored
    end

    test "keeps set bonuses independent of enchants and ordinary auras", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      {character, _} = Application.apply_spell(character, 2, 10, get_spell.(1), 0)
      source = {:item_set, 1, 1}
      equipped = EquipmentAuras.sync(character, enchants, get_spell, 1, [source, source])
      assert equipped.unit.max_health == 120
      assert length(equipped.unit.auras) == 4
      assert EquipmentAuras.sync(equipped, enchants, get_spell, 2, [source]) == equipped
      removed = EquipmentAuras.sync(equipped, enchants, get_spell, 3, [])
      assert removed.unit.max_health == 115
      assert length(removed.unit.auras) == 3
      assert EquipmentAuras.sync(equipped, [], get_spell, 4, [source]).unit.max_health == 110
    end

    test "survives death and cannot be cancelled by the client", %{character: character, get_spell: get_spell} do
      equipped = EquipmentAuras.sync(character, [], get_spell, 0, [{:item_set, 1, 1}])
      {cancelled, _} = Aura.cancel_spell(equipped, 1, 10)
      assert cancelled.unit.auras == equipped.unit.auras
      dead = Core.take_damage(equipped, 1_000, 2, now: 100)
      assert length(dead.unit.auras) == 1
      {restored, _} = Death.resurrect(dead, 1.0, 200)
      assert restored.unit.health == 105
      assert EquipmentAuras.sync(restored, [], get_spell, 300, []).unit.max_health == 100
    end

    test "retains proc cooldowns across unrelated inventory changes", %{character: character, get_spell: get_spell} do
      equipped = EquipmentAuras.sync(character, [], get_spell, 0, [{:item_set, 1, 1}])
      [holder] = equipped.unit.auras
      equipped = put_in(equipped.unit.auras, [%{holder | next_proc_at: 5_000}])
      assert EquipmentAuras.sync(equipped, [], get_spell, 100, [{:item_set, 1, 1}]) == equipped
    end

    test "fires set procs through combat reactions and removes them with the set", %{character: character} do
      spell = %Spell{
        id: 4,
        proc_type_mask: 4,
        proc_chance: 100,
        proc_rule: %ProcRule{cooldown_ms: 1_000},
        effects: [%Effect{type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 5}]
      }

      equipped = EquipmentAuras.sync(character, [], fn 4 -> spell end, 0, [{:item_set, 1, 4}])
      context = %{victim_guid: 2, outcome: :normal, proc_type: :deal_melee_swing, now: 100}
      {procced, events} = Aura.reactions(equipped, :melee_hit_dealt, context)
      assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 2, spell_id: 5}] = events
      procced = EquipmentAuras.sync(procced, [], fn 4 -> spell end, 200, [{:item_set, 1, 4}])
      assert {_, []} = Aura.reactions(procced, :melee_hit_dealt, %{context | now: 200})
      removed = EquipmentAuras.sync(procced, [], fn _ -> nil end, 300, [])
      assert {_, []} = Aura.reactions(removed, :melee_hit_dealt, %{context | now: 2_000})
    end

    test "publishes and removes set spell modifiers", %{character: character} do
      spell = %Spell{
        id: 3,
        effects: [%Effect{type: :apply_aura, aura: :add_flat_modifier, misc_value: 0, class_mask: 1, base_points: 20}]
      }

      equipped = EquipmentAuras.sync(character, [], fn 3 -> spell end, 0, [{:item_set, 1, 3}])
      {equipped, events} = Effects.drain(equipped)
      assert Enum.any?(events, &match?(%Effects.SpellModifier{amount: 20}, &1))
      {_, events} = equipped |> EquipmentAuras.sync([], fn _ -> nil end, 100, []) |> Effects.drain()
      assert Enum.any?(events, &match?(%Effects.SpellModifier{amount: 0}, &1))
    end

    test "reconciles form restrictions without dropping unrestricted bonuses", %{character: character} do
      spells = %{
        1 => %Spell{
          id: 1,
          stances: 1,
          effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 5}]
        },
        2 => %Spell{id: 2, effects: [%Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: 1}]},
        3 => %Spell{id: 3, effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 10}]}
      }

      sources = [{:item_set, 1, 1}, {:item_set, 1, 3}]
      equipped = EquipmentAuras.sync(character, [], &Map.get(spells, &1), 0, sources)
      assert equipped.unit.max_health == 110
      {shifted, _} = Application.apply_spell(equipped, 1, 10, spells[2], 10)
      shifted = EquipmentAuras.sync(shifted, [], &Map.get(spells, &1), 10, sources)
      assert shifted.unit.max_health == 115
      {restored, _} = Aura.cancel_spell(shifted, 2, 20)
      restored = EquipmentAuras.sync(restored, [], &Map.get(spells, &1), 20, sources)
      assert restored.unit.max_health == 110
    end
  end

  describe "resync/4" do
    test "adds armor and weapon damage to their matching inputs without accumulation", %{character: character} do
      template = %ItemTemplate{entry: 100, delay: 2_000}
      item = Item.build(template, 10)

      unit = %{
        character.unit
        | base_normal_resistance: 0,
          base_min_damage: 10.0,
          base_max_damage: 20.0,
          base_attack_time: 2_000,
          base_offhand_min_damage: 3.0,
          base_offhand_max_damage: 5.0,
          base_ranged_min_damage: 7.0,
          base_ranged_max_damage: 9.0
      }

      character = %{character | unit: unit}
      enchantment = %ItemEnchantment{effects: [%{type: 2, amount: 5}, %{type: 4, amount: 8, spell_id: 0}]}
      entries = [{:mainhand, item, 0, enchantment}]
      equipped = EquipmentStats.resync(character, fn _ -> nil end, fn _ -> nil end, entries)
      assert equipped.unit.min_damage == 15.0
      assert equipped.unit.max_damage == 25.0
      assert equipped.unit.min_offhand_damage == 3.0
      assert equipped.unit.min_ranged_damage == 7.0
      assert equipped.unit.normal_resistance == 8
      assert EquipmentStats.resync(equipped, fn _ -> nil end, fn _ -> nil end, entries) == equipped
    end
  end

  defp equipment(_context) do
    character = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, auras: [], level: 10}
    }

    enchantment = %ItemEnchantment{id: 41, effects: [%{type: 3, spell_id: 1}]}
    item = Item.build(%ItemTemplate{entry: 100}, 10)
    other = Item.build(%ItemTemplate{entry: 101}, 11)
    enchants = [{:chest, item, 0, enchantment}, {:wrists, other, 0, enchantment}]
    spell = %Spell{id: 1, effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 5}]}
    %{character: character, enchants: enchants, get_spell: fn 1 -> spell end}
  end
end
