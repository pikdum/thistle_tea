defmodule ThistleTea.Game.Entity.Logic.SpellResistTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.SpellResist

  describe "magic_hit_chance_bp/3" do
    test "is 96 percent at even level" do
      assert SpellResist.magic_hit_chance_bp(20, 20, false) == 9_600
    end

    test "drops one percent per level up to two levels" do
      assert SpellResist.magic_hit_chance_bp(20, 21, false) == 9_500
      assert SpellResist.magic_hit_chance_bp(20, 22, false) == 9_400
    end

    test "drops eleven percent per level past two against mobs" do
      assert SpellResist.magic_hit_chance_bp(20, 23, false) == 8_300
      assert SpellResist.magic_hit_chance_bp(20, 24, false) == 7_200
    end

    test "drops seven percent per level past two against players" do
      assert SpellResist.magic_hit_chance_bp(20, 23, true) == 8_700
    end

    test "never drops below the 22 percent hit floor" do
      assert SpellResist.magic_hit_chance_bp(20, 60, false) == 2_200
    end

    test "never exceeds 99 percent" do
      assert SpellResist.magic_hit_chance_bp(60, 1, false) == 9_900
    end
  end

  describe "magic_hit?/4" do
    test "hits when the roll is under the hit chance" do
      assert SpellResist.magic_hit?(20, 20, false, roll: 9_599)
      refute SpellResist.magic_hit?(20, 20, false, roll: 9_600)
    end
  end

  describe "resist_chance/4" do
    test "is zero with no resistance at even level" do
      assert SpellResist.resist_chance(0, 20, true, 0) == 0.0
    end

    test "scales with resistance and caster level" do
      assert_in_delta SpellResist.resist_chance(100, 60, false, 0), 0.25, 0.001
    end

    test "adds innate level-based resistance against higher-level creatures" do
      # 8 * 3 * 20 / 63 = 7 bonus resistance
      assert_in_delta SpellResist.resist_chance(0, 20, true, 3), 7 * 0.15 / 20, 0.001
    end

    test "caps at 75 percent" do
      assert SpellResist.resist_chance(10_000, 20, false, 0) == 0.75
    end
  end

  describe "resist_fraction/3" do
    test "zero resist chance never resists" do
      assert SpellResist.resist_fraction(0, 20, roll: 0, level_diff: 0) == 0.0
      assert SpellResist.resist_fraction(0, 20, roll: 99, level_diff: 0) == 0.0
    end

    test "high resistance produces partial resist buckets" do
      # 300 resistance vs level 60 caster -> 75% average resist chance
      assert SpellResist.resist_fraction(300, 60, roll: 0, target_creature?: false) == 0.75
      assert SpellResist.resist_fraction(300, 60, roll: 90, target_creature?: false) == 0.5
      assert SpellResist.resist_fraction(300, 60, roll: 96, target_creature?: false) == 0.25
    end

    test "dot ticks are a tenth as likely to resist" do
      refute SpellResist.resist_fraction(300, 60, roll: 50, target_creature?: false, dot?: true) ==
               SpellResist.resist_fraction(300, 60, roll: 50, target_creature?: false)
    end
  end

  describe "resisted_amount/4" do
    test "returns the resisted portion of the damage" do
      assert SpellResist.resisted_amount(100, 300, 60, roll: 0, target_creature?: false) == 75
    end

    test "returns zero for zero damage" do
      assert SpellResist.resisted_amount(0, 300, 60, roll: 0) == 0
    end
  end
end
