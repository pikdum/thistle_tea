defmodule ThistleTea.Game.Entity.Logic.ExperienceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Experience

  describe "kill_xp/3" do
    test "calculates same-level kill XP" do
      assert Experience.kill_xp(1, 1) == 50
      assert Experience.kill_xp(10, 10) == 95
    end

    test "caps higher-level kill bonus at four levels" do
      assert Experience.kill_xp(10, 14) == Experience.kill_xp(10, 15)
    end

    test "returns no XP for gray mobs" do
      assert Experience.kill_xp(10, 4) == 0
      assert Experience.kill_xp(10, 5) > 0
    end

    test "applies elite, multiplier, and no-XP flags" do
      assert Experience.kill_xp(1, 1, elite?: true) == 100
      assert Experience.kill_xp(1, 1, experience_multiplier: 1.5) == 75
      assert Experience.kill_xp(1, 1, extra_flags: 0x40) == 0
    end
  end
end
