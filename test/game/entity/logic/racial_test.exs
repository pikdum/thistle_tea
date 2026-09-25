defmodule ThistleTea.Game.Entity.Logic.RacialTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Racial
  alias ThistleTea.Game.Entity.Logic.Stats

  describe "berserking_percent/2" do
    test "uses whole health percentages and caps the bonus at forty percent health" do
      for {health, expected} <- [{1000, 10}, {999, 10}, {970, 11}, {700, 20}, {410, 29}, {409, 30}, {1, 30}] do
        assert Racial.berserking_percent(health, 1000) == expected
      end

      assert Racial.berserking_percent(1100, 1000) == 10
      assert Racial.berserking_percent(0, 0) == 10
    end
  end

  describe "blood_fury/2" do
    test "captures stat-derived attack power without flat attack-power bonuses" do
      unit =
        Stats.recompute(%Unit{
          class: 1,
          level: 60,
          base_strength: 100,
          base_agility: 50,
          equipment_bonuses: %{strength: 20, attack_power: 400},
          auras: []
        })

      character = %Character{object: %Object{guid: 1}, unit: unit, internal: %Internal{}}
      assert unit.attack_power == 800

      assert {^character, [penalty, buff]} = Racial.blood_fury(character, 25)
      assert %Effects.TriggerSpell{spell_id: 23_230} = penalty
      assert %Effects.TriggerSpell{spell_id: 23_234, amount: 100, slot: 0} = buff
    end

    test "zero attack power still applies the penalty and creatures do not gain the racial" do
      character = %Character{object: %Object{guid: 1}, unit: %Unit{class: 9, level: 1, strength: 10}}
      assert {^character, [%Effects.TriggerSpell{spell_id: 23_230}]} = Racial.blood_fury(character, 25)
      creature = %Mob{object: %Object{guid: 2}, unit: character.unit}
      assert {^creature, []} = Racial.blood_fury(creature, 25)
    end
  end

  describe "blood_fury/3" do
    test "fractional attack power rounds stochastically like the reference" do
      character = %Character{object: %Object{guid: 1}, unit: %Unit{class: 1, level: 59, strength: 100}}

      assert {^character, [_penalty, %Effects.TriggerSpell{amount: 89}]} =
               Racial.blood_fury(character, 25, fn -> 0.1 end)

      assert {^character, [_penalty, %Effects.TriggerSpell{amount: 90}]} =
               Racial.blood_fury(character, 25, fn -> 0.9 end)
    end
  end
end
