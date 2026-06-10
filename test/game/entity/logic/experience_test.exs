defmodule ThistleTea.Game.Entity.Logic.ExperienceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Experience

  describe "quest_xp/3" do
    test "full xp at or below quest level plus five" do
      assert Experience.quest_xp(2, 540, 1) == 900
      assert Experience.quest_xp(2, 540, 7) == 900
    end

    test "scales down as the player outlevels the quest" do
      assert Experience.quest_xp(2, 540, 8) == 720
      assert Experience.quest_xp(2, 540, 9) == 540
      assert Experience.quest_xp(2, 540, 10) == 360
      assert Experience.quest_xp(2, 540, 11) == 180
      assert Experience.quest_xp(2, 540, 12) == 90
    end

    test "no money max level means no xp" do
      assert Experience.quest_xp(10, 0, 10) == 0
    end
  end

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
