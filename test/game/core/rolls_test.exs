defmodule ThistleTea.Game.Core.RollsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Rolls

  describe "integer/4" do
    test "returns a pinned roll clamped to the range" do
      rolls = Rolls.fixed(melee: 9_999, mechanic: -5)

      assert Rolls.integer(rolls, :melee, 0, 9_999) == 9_999
      assert Rolls.integer(rolls, :melee, 0, 99) == 99
      assert Rolls.integer(rolls, :mechanic, 0, 99) == 0
    end

    test "draws unpinned rolls within the range" do
      rolls = Rolls.fixed(melee: 1)

      for _ <- 1..50 do
        assert Rolls.integer(rolls, :weapon_damage, 10, 12) in 10..12
        assert Rolls.integer(Rolls.system(), :melee, 0, 3) in 0..3
      end
    end
  end

  describe "uniform/2" do
    test "returns a pinned float and draws the rest" do
      rolls = Rolls.fixed(spell_crit: 0.25)

      assert Rolls.uniform(rolls, :spell_crit) == 0.25
      assert Rolls.uniform(rolls, :other) >= 0.0
      assert Rolls.uniform(rolls, :other) < 1.0
    end
  end

  describe "pinned/2" do
    test "renames only the pinned rolls" do
      rolls = Rolls.fixed(melee: 9_999)

      assert Rolls.pinned(rolls, melee: :roll, melee_crit: :crit_roll) == [roll: 9_999]
      assert Rolls.pinned(Rolls.system(), melee: :roll) == []
    end
  end
end
