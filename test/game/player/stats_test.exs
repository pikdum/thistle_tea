defmodule ThistleTea.Game.Player.StatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Player.Stats

  describe "melee_attack_power/4" do
    test "warrior scales with level and strength" do
      assert Stats.melee_attack_power(1, 10, 30, 20) == 10 * 3 + 30 * 2 - 20
    end

    test "rogue scales with level, strength, and agility" do
      assert Stats.melee_attack_power(4, 10, 20, 25) == 10 * 2 + 20 + 25 - 20
    end

    test "shaman scales with level and double strength" do
      assert Stats.melee_attack_power(7, 10, 20, 15) == 10 * 2 + 20 * 2 - 20
    end

    test "druid ignores level" do
      assert Stats.melee_attack_power(11, 10, 20, 15) == 20 * 2 - 20
    end

    test "casters scale with strength only" do
      assert Stats.melee_attack_power(8, 10, 15, 15) == 5
      assert Stats.melee_attack_power(5, 10, 15, 15) == 5
    end

    test "never goes negative" do
      assert Stats.melee_attack_power(8, 1, 3, 3) == 0
    end
  end

  describe "ranged_attack_power/3" do
    test "hunter scales with level and double agility" do
      assert Stats.ranged_attack_power(3, 10, 25) == 10 * 2 + 25 * 2 - 10
    end

    test "warrior and rogue scale with level and agility" do
      assert Stats.ranged_attack_power(1, 10, 25) == 10 + 25 - 10
      assert Stats.ranged_attack_power(4, 10, 25) == 10 + 25 - 10
    end

    test "others scale with agility only" do
      assert Stats.ranged_attack_power(8, 10, 25) == 15
    end
  end

  describe "stamina_health_bonus/1" do
    test "first 20 points give 1 health each, the rest 10" do
      assert Stats.stamina_health_bonus(15) == 15
      assert Stats.stamina_health_bonus(25) == 20 + 50
    end
  end
end
