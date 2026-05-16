defmodule ThistleTea.Game.Player.StatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Player.Stats

  describe "get!/3" do
    test "loads race, class, and level stats from Mangos" do
      stats = Stats.get!(1, 1, 1)

      assert stats.strength == 23
      assert stats.agility == 20
      assert stats.stamina == 22
      assert stats.intellect == 20
      assert stats.spirit == 21
      assert stats.base_health == 20
      assert stats.base_mana == 0
      assert stats.max_health == 60
      assert stats.max_mana == 0
      assert stats.next_level_xp == 400
    end
  end
end
