defmodule ThistleTea.Game.Entity.Logic.GatheringTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Gathering
  alias ThistleTea.Game.Entity.Logic.Skills

  describe "gain_chance/4" do
    test "uses gathering difficulty thresholds and mining reductions" do
      assert Enum.map([1, 25, 50, 100], &Gathering.gain_chance(182, &1, 0)) == [100, 75, 25, 0]
      assert Gathering.gain_chance(186, 74, 65) == 100
      assert Gathering.gain_chance(186, 75, 65) == 50
      assert Gathering.gain_chance(186, 150, 150) == 25
      assert Gathering.gain_chance(633, 225, 225) == 100
      assert Gathering.gain_chance(393, 75, 65, 2) == 100
    end
  end

  describe "skill_up/5" do
    test "preserves trained rank and slot while respecting caps and failed rolls" do
      skills = Skills.learn_rank(%{}, 186, 75)
      assert {:gained, updated} = Gathering.skill_up(skills, 186, 0, 0)
      assert updated[186] == %{skills[186] | value: 2}
      assert Gathering.skill_up(Skills.max_out(skills), 186, 75, 0) == :unchanged
      assert Gathering.skill_up(%{}, 186, 0, 0) == :unchanged
      assert Gathering.skill_up(skills, 186, 0, 100) == :unchanged
    end
  end

  describe "attempt?/4" do
    test "orange attempts can fail but maximum gathering cannot" do
      refute Gathering.attempt?(186, 65, 65, 64)
      assert Gathering.attempt?(186, 65, 65, 65)
      assert Gathering.attempt?(182, 300, 300, 275)
      refute Gathering.attempt?(633, 300, 300, 275)
    end
  end

  describe "replenish?/6" do
    test "guarantees minimum harvests and caps exhaustion" do
      assert Gathering.replenish?(1, 2, 4, 1, 0, 99)
      assert Gathering.replenish?(2, 2, 4, 1, 0, 63)
      refute Gathering.replenish?(2, 2, 4, 1, 0, 65)
      refute Gathering.replenish?(4, 2, 4, 300, 0, 0)
      refute Gathering.replenish?(1, 1, 1, 300, 0, 0)
    end
  end
end
