defmodule ThistleTea.Game.Spell.TargetLimitTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.TargetLimit

  describe "select/3" do
    test "retains an eligible primary target within the cap" do
      assert TargetLimit.select([2, 3, 4, 5], %Spell{max_targets: 2}, 5) == [2, 5]
      assert TargetLimit.select([2, 3, 4, 5], %Spell{max_targets: 1}, 5) == [5]
    end

    test "never inserts an ineligible primary target" do
      assert TargetLimit.select([2, 3, 4], %Spell{max_targets: 2}, 9) == [2, 3]
      assert TargetLimit.select([], %Spell{max_targets: 2}, 9) == []
    end

    test "deduplicates before counting slots and preserves uncapped order" do
      assert TargetLimit.select([2, 2, 3, 4], %Spell{max_targets: 2}) == [2, 3]
      assert TargetLimit.select([2, 2, 3, 4], %Spell{}, 4) == [2, 3, 4]
      assert TargetLimit.select([2, 3], %Spell{max_targets: 2}, 2) == [2, 3]
    end
  end
end
