defmodule ThistleTea.Game.Entity.Logic.EquipmentEnchantmentsTest do
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
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.EquipmentEnchantments
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:equipment]

  describe "sync/4" do
    test "projects skill enchant bonuses and clears them on removal", %{character: character, enchants: [entry | _]} do
      {slot, item, enchant_slot, enchantment} = entry
      enchantment = %{enchantment | effects: [%{type: 3, spell_id: 3}]}
      spell = %Spell{id: 3, effects: [%Effect{type: :apply_aura, aura: :mod_skill, misc_value: 95, base_points: 1}]}
      equipped = EquipmentEnchantments.sync(character, [{slot, item, enchant_slot, enchantment}], fn 3 -> spell end, 0)
      assert equipped.player.skill_bonuses == %{95 => {1, 0}}
      assert equipped.player.skills == character.player.skills
      removed = EquipmentEnchantments.sync(equipped, [], fn _ -> nil end, 100)
      assert removed.player.skill_bonuses == %{}
    end

    test "stacks identical enchants by source and removes only unequipped sources", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      both = EquipmentEnchantments.sync(character, enchants, get_spell, 0)
      assert both.unit.max_health == 110
      assert both.unit.health == 100
      assert length(both.unit.auras) == 2
      assert Enum.all?(both.unit.auras, &is_nil(&1.slot))
      assert EquipmentEnchantments.sync(both, enchants, get_spell, 100) == both
      one = EquipmentEnchantments.sync(both, tl(enchants), get_spell, 200)
      assert one.unit.max_health == 105
      assert length(one.unit.auras) == 1
      removed = EquipmentEnchantments.sync(one, [], get_spell, 300)
      assert removed.unit.max_health == 100
      assert removed.unit.auras == []
    end

    test "retains enchant passives through death and resurrection", %{
      character: character,
      enchants: enchants,
      get_spell: get_spell
    } do
      equipped = EquipmentEnchantments.sync(character, enchants, get_spell, 0)
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
      equipped = EquipmentEnchantments.sync(character, [first], get_spell, 0)
      {slot, item, enchant_slot, enchantment} = first
      new = {slot, item, enchant_slot, %{enchantment | effects: [%{type: 3, spell_id: 2}]}}
      spell = %Spell{id: 2, effects: [%Effect{type: :apply_aura, aura: :mod_increase_health, base_points: 20}]}
      replaced = EquipmentEnchantments.sync(equipped, [new], fn 2 -> spell end, 100)
      assert replaced.unit.max_health == 120
      assert length(replaced.unit.auras) == 1
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
