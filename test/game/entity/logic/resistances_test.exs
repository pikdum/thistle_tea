defmodule ThistleTea.Game.Entity.Logic.ResistancesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_character]

  describe "recompute/1" do
    test "agility contributes outside the base armor multiplier" do
      unit = %Unit{
        base_agility: 30,
        equipment_bonuses: %{agility: 10, armor: 100},
        auras: [holder(:mod_stat, 5, 1), holder(:mod_base_resistance_percent, 180, 1)]
      }

      bear = Stats.recompute(unit)
      assert bear.agility == 45
      assert bear.normal_resistance == 370
      assert Stats.recompute(bear) == bear
      assert Stats.recompute(%{bear | auras: []}).normal_resistance == 180
      assert Stats.recompute(%{bear | equipment_bonuses: %{}}).normal_resistance == 70
    end

    test "distinguishes ordinary creatures and hunter pets from players" do
      unit = %Unit{base_agility: 50, base_normal_resistance: 100, auras: []}
      assert Stats.recompute(unit).normal_resistance == 200
      creature = %{unit | stat_model: :creature}
      assert Stats.recompute(creature).normal_resistance == 150
      assert Stats.recompute(%{creature | attack_power_model: :hunter_pet}).normal_resistance == 200
    end

    test "scales base flats before ordinary bonuses and multiplies independent percentages" do
      unit = %Unit{
        base_fire_resistance: 100,
        base_frost_resistance: 25,
        equipment_bonuses: %{fire: 50},
        auras: [
          holder(:mod_base_resistance, 50, 20),
          holder(:mod_base_resistance_percent, 20, 4),
          holder(:mod_base_resistance_percent, 50, 4),
          holder(:mod_resistance, 40, 4),
          holder(:mod_resistance_percent, -20, 4),
          holder(:mod_resistance_percent, -25, 4)
        ]
      }

      modified = Stats.recompute(unit)
      assert modified.fire_resistance == 240
      assert modified.frost_resistance == 75
      assert modified.shadow_resistance == 0
      assert modified.base_fire_resistance == 100

      assert Stats.recompute(%{modified | auras: Enum.reverse(modified.auras)}) ==
               %{modified | auras: Enum.reverse(modified.auras)}

      assert Stats.recompute(%{modified | auras: []}).fire_resistance == 150
    end

    test "truncates after combining fractional base and stat contributions" do
      unit = %Unit{
        base_agility: 41,
        base_intellect: 125,
        base_normal_resistance: 101,
        auras: [
          holder(:mod_base_resistance_percent, 10, 1),
          holder(:mod_resistance_of_stat_percent, 50, 1),
          holder(:mod_resistance, 30, 1),
          holder(:mod_resistance_percent, 50, 1)
        ]
      }

      assert Stats.recompute(unit).normal_resistance == 428
    end

    test "stack changes affect a single factor without retaining stale values" do
      stacked = %{holder(:mod_resistance_percent, 20, 4) | stacks: 3}
      separate = holder(:mod_resistance_percent, 50, 4)
      unit = %Unit{base_fire_resistance: 100, auras: [stacked, separate]}
      assert Stats.recompute(unit).fire_resistance == 240
      assert Stats.recompute(%{unit | auras: [%{stacked | stacks: 2}, separate]}).fire_resistance == 210
      assert Stats.recompute(%{unit | auras: [separate]}).fire_resistance == 150
    end

    test "debuffs cannot create negative resistance but preserve innate vulnerabilities" do
      penalty = holder(:mod_resistance, -200, 4)
      unit = %Unit{base_fire_resistance: 50, auras: [penalty]}
      assert Stats.recompute(unit).fire_resistance == 0
      assert Stats.recompute(%{unit | base_fire_resistance: -50}).fire_resistance == -250

      suppressed = %{unit | auras: [holder(:mod_resistance_percent, -150, 4)]}
      assert Stats.recompute(suppressed).fire_resistance == 0
    end
  end

  describe "apply_spell/5" do
    test "application, replacement, expiry, and removal update combat armor", %{character: character} do
      spell = %Spell{
        id: 819,
        duration_ms: 1_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_base_resistance, base_points: 1_000, misc_value: 1}]
      }

      {buffed, _events} = AuraLogic.apply_spell(character, 1, 60, spell, 0)
      assert buffed.unit.normal_resistance == 1_100
      attack = %{caster_level: 60, caster_player?: true, spell_school_mask: 1, skill: 300}
      plain_hit = AttackTable.resolve(character, attack, 1_000, roll: 9_999)
      armored_hit = AttackTable.resolve(buffed, attack, 1_000, roll: 9_999)
      assert plain_hit.outcome == :normal
      assert armored_hit.outcome == :normal
      assert plain_hit.damage == 983
      assert armored_hit.damage == 834

      stronger = %{spell | effects: [%{hd(spell.effects) | base_points: 2_000}]}
      {replaced, _events} = AuraLogic.apply_spell(buffed, 1, 60, stronger, 500)
      assert replaced.unit.normal_resistance == 2_100
      assert length(replaced.unit.auras) == 1
      {expired, _events} = AuraLogic.tick(replaced, 1_501)
      assert expired.unit.normal_resistance == 100
      {removed, _events} = AuraLogic.remove_spells(buffed, [819], 100)
      assert removed.unit.normal_resistance == 100
      assert removed.unit.base_normal_resistance == nil
    end
  end

  defp build_character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: Stats.recompute(%Unit{level: 60, health: 1_000, max_health: 1_000, base_agility: 50, auras: []}),
        player: %Player{},
        internal: %Internal{}
      }
    }
  end

  defp holder(type, amount, mask) do
    %Holder{spell: %Spell{id: 100}, auras: [%Aura{type: type, amount: amount, misc_value: mask}]}
  end
end
