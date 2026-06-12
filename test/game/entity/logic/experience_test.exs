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

  describe "group_rate/1" do
    test "no bonus for one or two members" do
      assert Experience.group_rate(1) == 1.0
      assert Experience.group_rate(2) == 1.0
    end

    test "scales up to five members" do
      assert Experience.group_rate(3) == 1.166
      assert Experience.group_rate(4) == 1.3
      assert Experience.group_rate(5) == 1.4
      assert Experience.group_rate(6) == 1.4
    end
  end

  describe "group_shares/3" do
    test "splits XP by level weight" do
      shares = Experience.group_shares([%{guid: 1, level: 10}, %{guid: 2, level: 10}], 10)
      base = Experience.kill_xp(10, 10)

      assert shares == [{1, trunc(base * 10 / 20)}, {2, trunc(base * 10 / 20)}]
    end

    test "applies the group bonus rate for three members" do
      members = [%{guid: 1, level: 10}, %{guid: 2, level: 10}, %{guid: 3, level: 10}]
      shares = Experience.group_shares(members, 10)
      base = Experience.kill_xp(10, 10)

      expected = trunc(base * 1.166 * 10 / 30)
      assert shares == [{1, expected}, {2, expected}, {3, expected}]
    end

    test "weights shares toward higher-level members" do
      shares = Experience.group_shares([%{guid: 1, level: 20}, %{guid: 2, level: 10}], 20)
      base = Experience.kill_xp(20, 20)

      assert shares == [{1, trunc(base * 20 / 30)}, {2, trunc(base * 10 / 30)}]
    end

    test "gray mob for everyone yields zero shares" do
      shares = Experience.group_shares([%{guid: 1, level: 60}, %{guid: 2, level: 60}], 1)
      assert shares == [{1, 0}, {2, 0}]
    end

    test "halves shares plus one when the top member is gray but a lower member is not" do
      shares = Experience.group_shares([%{guid: 1, level: 60}, %{guid: 2, level: 20}], 21)

      base = Experience.kill_xp(20, 21)
      assert shares == [{1, 0}, {2, trunc(base * 1.0 * 20 / 80 / 2) + 1}]
    end

    test "empty member list yields no shares" do
      assert Experience.group_shares([], 10) == []
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
