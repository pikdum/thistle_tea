defmodule ThistleTea.Game.Entity.Logic.StatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell

  defp mage_unit do
    %Unit{
      class: 8,
      race: 1,
      level: 60,
      base_strength: 35,
      base_agility: 41,
      base_stamina: 45,
      base_intellect: 125,
      base_spirit: 126,
      base_health: 1360,
      base_mana: 1273,
      health: 100,
      power1: 100,
      auras: []
    }
  end

  defp holder(auras) do
    %Holder{spell: %Spell{id: 1, name: "Test"}, slot: 0, caster_guid: 1, auras: auras}
  end

  defp recompute(unit), do: apply(&Stats.recompute/1, [unit])

  describe "recompute/1" do
    test "creature models use stat deltas for resources and agility for armor" do
      unit = %Unit{
        stat_model: :creature,
        base_health: 100,
        base_mana: 0,
        base_stamina: 10,
        base_intellect: 10,
        base_agility: 10,
        base_normal_resistance: 100,
        health: 100,
        power1: 0,
        auras: []
      }

      original = recompute(unit)
      assert original.max_health == 100
      assert original.max_power1 == 0
      assert original.normal_resistance == 110
      buff = holder([%Aura{type: :mod_stat, amount: 10, misc_value: -1}])
      buffed = recompute(%{original | auras: [buff]})
      assert buffed.max_health == 200
      assert buffed.max_power1 == 150
      assert buffed.normal_resistance == 120
      assert recompute(buffed) == buffed
      assert recompute(%{buffed | auras: []}) == original
      changed = recompute(%{buffed | base_stamina: 20, base_health: 300})
      assert changed.max_health == 400
      assert recompute(%{changed | auras: []}).max_health == 300
      assert recompute(%{original | base_health: 0}).max_health == 1
      assert recompute(%{buffed | base_health: 0}).max_health == 100
    end

    test "scales base and item stats before flat auras and total percentages" do
      auras = [
        %Aura{type: :mod_percent_stat, amount: -75, misc_value: -1},
        %Aura{type: :mod_stat, amount: 31, misc_value: 3},
        %Aura{type: :mod_total_stat_percent, amount: 10, misc_value: -1}
      ]

      unit = recompute(%{mage_unit() | equipment_bonuses: %{intellect: 35}, auras: [holder(auras)]})

      assert unit.intellect == 78
      assert unit.stamina == 12
      assert unit.max_power1 == 2163
      assert unit.max_health == 1372
      assert unit.base_intellect == 125
      assert unit.equipment_bonuses.intellect == 35
      assert recompute(unit) == unit
    end

    test "multiplies independent percentages in both stat layers" do
      for type <- [:mod_percent_stat, :mod_total_stat_percent] do
        first = holder([%Aura{type: type, amount: 20, misc_value: 3}])
        second = holder([%Aura{type: type, amount: 50, misc_value: 3}])

        for holders <- [[first, second], [second, first]] do
          unit = recompute(%{mage_unit() | auras: holders})
          assert unit.intellect == 225
          assert unit.strength == 35
        end
      end
    end

    test "scales a holder's percentage by its remaining stacks" do
      for type <- [:mod_percent_stat, :mod_total_stat_percent] do
        stacked = %{holder([%Aura{type: type, amount: 20, misc_value: 3}]) | stacks: 3}
        base = %{mage_unit() | auras: [stacked]}
        assert recompute(base).intellect == 200
        assert recompute(%{base | auras: [%{stacked | stacks: 2}]}).intellect == 175
        assert recompute(%{base | auras: []}).intellect == 125
      end
    end

    test "clamps percentage penalties and ignores invalid stat selectors" do
      auras = [
        %Aura{type: :mod_percent_stat, amount: -150, misc_value: 3},
        %Aura{type: :mod_stat, amount: 31, misc_value: 3},
        %Aura{type: :mod_percent_stat, amount: 100, misc_value: -2},
        %Aura{type: :mod_percent_stat, amount: 100, misc_value: 5}
      ]

      unit = recompute(%{mage_unit() | auras: [holder(auras)]})
      assert unit.intellect == 31
      assert unit.stamina == 45
      assert recompute(%{unit | auras: []}).intellect == 125
    end

    test "uses changed base stats and gear while percentage auras remain active" do
      bonus = holder([%Aura{type: :mod_percent_stat, amount: 20, misc_value: 3}])
      unit = recompute(%{mage_unit() | auras: [bonus]})
      changed = recompute(%{unit | base_intellect: 150, equipment_bonuses: %{intellect: 50}})
      assert changed.intellect == 240
      assert recompute(%{changed | auras: []}).intellect == 200
    end

    test "does not invent base stats for creatures" do
      bonus = holder([%Aura{type: :mod_percent_stat, amount: 100, misc_value: -1}])
      unit = recompute(%Unit{strength: 50, max_health: 500, auras: [bonus]})
      assert unit.strength == 50
      assert unit.max_health == 500
      assert unit.base_strength == nil
    end

    test "selects exclusive resistance bonuses and penalties independently for each school" do
      auras = [
        %Aura{type: :mod_resistance_exclusive, amount: 20, misc_value: 126},
        %Aura{type: :mod_resistance_exclusive, amount: 60, misc_value: 4},
        %Aura{type: :mod_resistance_exclusive, amount: 40, misc_value: 20},
        %Aura{type: :mod_resistance_exclusive, amount: -10, misc_value: 126},
        %Aura{type: :mod_resistance_exclusive, amount: -25, misc_value: 16},
        %Aura{type: :mod_resistance, amount: 8, misc_value: 126},
        %Aura{type: :mod_resistance, amount: 7, misc_value: 126}
      ]

      unit = recompute(%{mage_unit() | base_fire_resistance: 5, equipment_bonuses: %{fire: 10}, auras: [holder(auras)]})

      assert unit.fire_resistance == 80
      assert unit.frost_resistance == 30
      assert unit.nature_resistance == 25
      assert unit.shadow_resistance == 25
      assert unit.arcane_resistance == 25
      assert unit.holy_resistance == 25
      assert unit.normal_resistance == 0
      assert recompute(unit) == unit
    end

    test "falls back after stronger resistance effects end without losing weaker auras" do
      weak = holder([%Aura{type: :mod_resistance_exclusive, amount: 20, misc_value: 4}])
      strong = holder([%Aura{type: :mod_resistance_exclusive, amount: 60, misc_value: 4}])
      base = %{mage_unit() | base_fire_resistance: 5}

      for holders <- [[weak, strong], [strong, weak], [weak, strong, strong]] do
        active = recompute(%{base | auras: holders})
        assert active.fire_resistance == 65
        assert recompute(%{active | auras: [weak]}).fire_resistance == 25
        assert recompute(%{active | auras: []}).fire_resistance == 5
      end
    end

    test "compares stacked exclusive amounts before applying resistance multipliers" do
      stacked = %{holder([%Aura{type: :mod_resistance_exclusive, amount: 20, misc_value: 1}]) | stacks: 3}
      other = holder([%Aura{type: :mod_resistance_exclusive, amount: 50, misc_value: 1}])
      multiplier = holder([%Aura{type: :mod_resistance_percent, amount: 50, misc_value: 1}])

      unit = recompute(%{mage_unit() | base_normal_resistance: 100, auras: [stacked, other, multiplier]})

      assert unit.normal_resistance == 240
    end

    test "derives stats and maxima from base values" do
      unit = recompute(mage_unit())

      assert unit.stamina == 45
      assert unit.intellect == 125
      assert unit.max_health == 1360 + 20 + (45 - 20) * 10
      assert unit.max_power1 == 1273 + 20 + (125 - 20) * 15
    end

    test "is idempotent" do
      once = recompute(mage_unit())
      assert recompute(once) == once
    end

    test "predatory strikes adds level-scaled attack power in feral forms" do
      talent = %Holder{
        slot: 0,
        caster_guid: 1,
        spell: %Spell{id: 16_975, name: "Predatory Strikes"},
        auras: [%Aura{type: :dummy, amount: 150}]
      }

      druid = %{mage_unit() | class: 11, shapeshift_form: 1, auras: [talent]}
      plain = recompute(%{druid | auras: []})
      unit = recompute(druid)

      assert unit.attack_power == plain.attack_power + div(60 * 150, 100)
    end

    test "adds armor from intellect for resistance-of-stat auras" do
      arcane_resilience = %Aura{type: :mod_resistance_of_stat_percent, amount: 50, misc_value: 1}

      base = recompute(mage_unit())
      unit = recompute(%{mage_unit() | auras: [holder([arcane_resilience])]})

      assert unit.normal_resistance == base.normal_resistance + div(125 * 50, 100)
    end

    test "adds equipment and aura bonuses on top of base" do
      arcane_intellect = %Aura{type: :mod_stat, amount: 31, misc_value: 3}
      frost_armor = %Aura{type: :mod_resistance, amount: 200, misc_value: 1}

      unit = %{
        mage_unit()
        | equipment_bonuses: %{stamina: 10, intellect: 20, health: 50, mana: 30, armor: 80},
          auras: [holder([arcane_intellect, frost_armor])]
      }

      unit = recompute(unit)

      assert unit.stamina == 55
      assert unit.intellect == 176
      assert unit.normal_resistance == 280
      assert unit.max_health == 1360 + 20 + (55 - 20) * 10 + 50
      assert unit.max_power1 == 1273 + 20 + (176 - 20) * 15 + 30
    end

    test "base changes survive repeated aura recomputes" do
      aura = %Aura{type: :mod_stat, amount: 31, misc_value: 3}
      unit = recompute(%{mage_unit() | auras: [holder([aura])]})

      leveled = recompute(%{unit | base_stamina: 51, base_intellect: 133, base_health: 1397, base_mana: 1420})

      recomputed = recompute(leveled)

      assert recomputed.max_health == leveled.max_health
      assert recomputed.max_power1 == leveled.max_power1
      assert recomputed.max_health == 1397 + 20 + (51 - 20) * 10
      assert recomputed.max_power1 == 1420 + 20 + (133 + 31 - 20) * 15
    end

    test "clamps current health and mana to new maxima" do
      unit = %{mage_unit() | health: 99_999, power1: 99_999}
      unit = recompute(unit)

      assert unit.health == unit.max_health
      assert unit.power1 == unit.max_power1
    end

    test "leaves units without base pools untouched" do
      mob = %Unit{level: 10, health: 500, max_health: 500, power1: 0, max_power1: 0, auras: []}
      recomputed = recompute(mob)

      assert recomputed.max_health == 500
      assert recomputed.health == 500
      assert recomputed.stamina == nil
    end

    test "derives attack power and weapon damage from stats, gear, and auras" do
      battle_shout = %Aura{type: :mod_attack_power, amount: 60, misc_value: 0}

      unit = %{
        mage_unit()
        | class: 1,
          level: 60,
          base_strength: 145,
          base_attack_time: 3400,
          base_melee_attack_time: 3400,
          base_min_damage: 100.0,
          base_max_damage: 150.0,
          equipment_bonuses: %{attack_power: 40},
          auras: [holder([battle_shout])]
      }

      unit = recompute(unit)

      expected_ap = 60 * 3 + 145 * 2 - 20 + 40 + 60
      assert unit.attack_power == expected_ap
      assert_in_delta unit.min_damage, 100.0 + expected_ap / 14 * 3.4, 0.000001
      assert_in_delta unit.max_damage, 150.0 + expected_ap / 14 * 3.4, 0.000001
    end

    test "strength buffs raise attack power and weapon damage" do
      unit = %{
        mage_unit()
        | class: 1,
          base_strength: 100,
          base_attack_time: 2000,
          base_min_damage: 10.0,
          base_max_damage: 20.0
      }

      unbuffed = recompute(unit)

      strength_buff = %Aura{type: :mod_stat, amount: 30, misc_value: 0}
      buffed = recompute(%{unit | auras: [holder([strength_buff])]})

      assert buffed.attack_power == unbuffed.attack_power + 60
      assert buffed.min_damage > unbuffed.min_damage
    end

    test "agility raises hunter ranged weapon damage" do
      unit = %{
        mage_unit()
        | class: 3,
          level: 50,
          base_agility: 100,
          ranged_attack_time: 2500,
          base_ranged_min_damage: 20.0,
          base_ranged_max_damage: 30.0
      }

      unbuffed = recompute(unit)
      buffed = recompute(%{unit | auras: [holder([%Aura{type: :mod_stat, amount: 20, misc_value: 1}])]})

      assert buffed.ranged_attack_power == unbuffed.ranged_attack_power + 40
      assert buffed.min_ranged_damage > unbuffed.min_ranged_damage
      assert buffed.max_ranged_damage > unbuffed.max_ranged_damage
    end

    test "quiver haste derives ranged attack time without mutating its base" do
      unit = %{
        mage_unit()
        | class: 3,
          base_ranged_attack_time: 2800,
          ranged_attack_time: 2800,
          base_ranged_min_damage: 20.0,
          base_ranged_max_damage: 30.0,
          equipment_bonuses: %{ranged_haste: 14}
      }

      recomputed = recompute(unit)

      assert recomputed.ranged_attack_time == trunc(2800 * 100 / 114)
      assert recomputed.base_ranged_attack_time == 2800
      assert recompute(recomputed) == recomputed
    end

    test "druid forms derive armor, attack power, and feral weapon damage" do
      bear_armor = %Aura{type: :mod_base_resistance_percent, amount: 180, misc_value: 1}
      bear_ap = %Aura{type: :mod_attack_power, amount: 30}

      bear =
        recompute(%{
          mage_unit()
          | class: 11,
            level: 40,
            shapeshift_form: 5,
            base_strength: 80,
            base_agility: 70,
            base_normal_resistance: 100,
            base_attack_time: 2500,
            base_min_damage: 10.0,
            base_max_damage: 20.0,
            equipment_bonuses: %{armor: 200},
            auras: [holder([bear_armor, bear_ap])]
        })

      assert bear.normal_resistance == 840
      assert bear.attack_power == 170
      assert bear.base_attack_time == 2_500
      assert_in_delta bear.min_damage, 40 * 0.85 * 2.5 + 170 / 14 * 2.5, 0.01

      cat = recompute(%{bear | shapeshift_form: 1, auras: []})
      assert cat.attack_power == 80 * 2 + 70 - 20
      assert cat.base_attack_time == 1_000
    end

    test "skips weapon damage without base inputs" do
      mob = %Unit{level: 10, attack_power: 50, min_damage: 30.0, max_damage: 40.0, base_attack_time: 2000, auras: []}
      recomputed = recompute(mob)

      assert recomputed.min_damage == 30.0
      assert recomputed.max_damage == 40.0
      assert recomputed.attack_power == 50
    end

    test "applies mod_stat with misc -1 to all stats" do
      aura = %Aura{type: :mod_stat, amount: 5, misc_value: -1}
      unit = recompute(%{mage_unit() | auras: [holder([aura])]})

      assert unit.strength == 40
      assert unit.agility == 46
      assert unit.stamina == 50
      assert unit.intellect == 130
      assert unit.spirit == 131
    end
  end
end
