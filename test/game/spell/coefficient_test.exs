defmodule ThistleTea.Game.Spell.CoefficientTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  describe "value/3" do
    test "a spell_template coefficient wins over the cast-time formula" do
      spell = %Spell{cast_time_ms: 3_500, effects: []}
      effect = %Effect{type: :school_damage, bonus_coefficient: 0.8}

      assert Coefficient.value(spell, effect, :direct) == 0.8
    end

    test "direct damage defaults to clamped cast time over 3500" do
      effect = %Effect{type: :school_damage}

      assert_in_delta Coefficient.value(%Spell{cast_time_ms: 3_000, effects: [effect]}, effect, :direct),
                      3000 / 3500,
                      0.0001

      assert_in_delta Coefficient.value(%Spell{cast_time_ms: 0, effects: [effect]}, effect, :direct),
                      1500 / 3500,
                      0.0001

      assert_in_delta Coefficient.value(%Spell{cast_time_ms: 10_000, effects: [effect]}, effect, :direct),
                      2.0,
                      0.0001
    end

    test "spells learned under level 20 pay the level penalty" do
      effect = %Effect{type: :school_damage}
      spell = %Spell{cast_time_ms: 3_500, spell_level: 10, effects: [effect]}

      assert_in_delta Coefficient.value(spell, effect, :direct), 1.0 - 10 * 0.0375, 0.0001
    end

    test "pure DoTs split the coefficient across ticks" do
      effect = %Effect{type: :apply_aura, aura: :periodic_damage, amplitude_ms: 3_000}
      spell = %Spell{cast_time_ms: 0, duration_ms: 15_000, spell_level: 30, effects: [effect]}

      assert_in_delta Coefficient.value(spell, effect, :dot), 1.0 / 5, 0.0001
    end

    test "hybrid direct plus DoT spells split the bonus between portions" do
      direct = %Effect{type: :school_damage}
      periodic = %Effect{type: :apply_aura, aura: :periodic_damage, amplitude_ms: 3_000}
      spell = %Spell{cast_time_ms: 2_000, duration_ms: 15_000, spell_level: 30, effects: [direct, periodic]}

      direct_value = Coefficient.value(spell, direct, :direct)
      dot_value = Coefficient.value(spell, periodic, :dot)

      assert direct_value < 2_000 / 3500
      assert dot_value < 1.0 / 5
      assert direct_value > 0
      assert dot_value > 0
    end

    test "area effects receive half the bonus" do
      effect = %Effect{type: :school_damage, area_target?: true}
      spell = %Spell{cast_time_ms: 3_500, spell_level: 30, effects: [effect]}

      assert_in_delta Coefficient.value(spell, effect, :direct), 0.5, 0.0001
    end

    test "health leech spells receive half the bonus" do
      effect = %Effect{type: :health_leech}
      spell = %Spell{cast_time_ms: 3_500, spell_level: 30, effects: [effect]}

      assert_in_delta Coefficient.value(spell, effect, :direct), 0.5, 0.0001
    end

    test "extra control effects shave five percent each" do
      damage = %Effect{type: :school_damage}
      slow = %Effect{type: :apply_aura, aura: :mod_decrease_speed}
      spell = %Spell{cast_time_ms: 3_500, spell_level: 30, effects: [damage, slow]}

      assert_in_delta Coefficient.value(spell, damage, :direct), 0.95, 0.0001
    end

    test "channeled DoTs use the channel duration without the duration factor" do
      effect = %Effect{type: :apply_aura, aura: :periodic_damage, amplitude_ms: 1_000}

      spell = %Spell{
        cast_time_ms: 0,
        duration_ms: 5_000,
        spell_level: 30,
        attributes: MapSet.new([:channeled]),
        effects: [effect]
      }

      assert_in_delta Coefficient.value(spell, effect, :dot), 5_000 / 3500 / 5, 0.0001
    end
  end

  describe "bonus/4" do
    test "scales the benefit by the coefficient" do
      spell = %Spell{cast_time_ms: 3_500, effects: []}
      effect = %Effect{type: :school_damage, bonus_coefficient: 0.5}

      assert Coefficient.bonus(100, spell, effect, :direct) == 50
      assert Coefficient.bonus(0, spell, effect, :direct) == 0
      assert Coefficient.bonus(nil, spell, effect, :direct) == 0
    end
  end
end
