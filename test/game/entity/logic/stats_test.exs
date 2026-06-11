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

  describe "recompute/1" do
    test "derives stats and maxima from base values" do
      unit = Stats.recompute(mage_unit())

      assert unit.stamina == 45
      assert unit.intellect == 125
      assert unit.max_health == 1360 + 20 + (45 - 20) * 10
      assert unit.max_power1 == 1273 + 20 + (125 - 20) * 15
    end

    test "is idempotent" do
      once = Stats.recompute(mage_unit())
      assert Stats.recompute(once) == once
    end

    test "adds equipment and aura bonuses on top of base" do
      arcane_intellect = %Aura{type: :mod_stat, amount: 31, misc_value: 3}
      frost_armor = %Aura{type: :mod_resistance, amount: 200, misc_value: 1}

      unit = %{
        mage_unit()
        | equipment_bonuses: %{stamina: 10, intellect: 20, health: 50, mana: 30, armor: 80},
          auras: [holder([arcane_intellect, frost_armor])]
      }

      unit = Stats.recompute(unit)

      assert unit.stamina == 55
      assert unit.intellect == 176
      assert unit.normal_resistance == 280
      assert unit.max_health == 1360 + 20 + (55 - 20) * 10 + 50
      assert unit.max_power1 == 1273 + 20 + (176 - 20) * 15 + 30
    end

    test "base changes survive repeated aura recomputes" do
      aura = %Aura{type: :mod_stat, amount: 31, misc_value: 3}
      unit = Stats.recompute(%{mage_unit() | auras: [holder([aura])]})

      leveled = Stats.recompute(%{unit | base_stamina: 51, base_intellect: 133, base_health: 1397, base_mana: 1420})
      recomputed = Stats.recompute(leveled)

      assert recomputed.max_health == leveled.max_health
      assert recomputed.max_power1 == leveled.max_power1
      assert recomputed.max_health == 1397 + 20 + (51 - 20) * 10
      assert recomputed.max_power1 == 1420 + 20 + (133 + 31 - 20) * 15
    end

    test "clamps current health and mana to new maxima" do
      unit = %{mage_unit() | health: 99_999, power1: 99_999}
      unit = Stats.recompute(unit)

      assert unit.health == unit.max_health
      assert unit.power1 == unit.max_power1
    end

    test "leaves units without base pools untouched" do
      mob = %Unit{level: 10, health: 500, max_health: 500, power1: 0, max_power1: 0, auras: []}
      recomputed = Stats.recompute(mob)

      assert recomputed.max_health == 500
      assert recomputed.health == 500
      assert recomputed.stamina == nil
    end

    test "applies mod_stat with misc -1 to all stats" do
      aura = %Aura{type: :mod_stat, amount: 5, misc_value: -1}
      unit = Stats.recompute(%{mage_unit() | auras: [holder([aura])]})

      assert unit.strength == 40
      assert unit.agility == 46
      assert unit.stamina == 50
      assert unit.intellect == 130
      assert unit.spirit == 131
    end
  end
end
