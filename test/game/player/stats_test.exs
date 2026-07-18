defmodule ThistleTea.Game.Player.StatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Player.Stats

  describe "apply/2" do
    test "raises level-ranged skill caps to the new level" do
      character = %Character{
        unit: %Unit{
          race: 1,
          class: 1,
          level: 1,
          health: 50,
          max_health: 50,
          base_strength: 10,
          base_agility: 10,
          base_stamina: 10,
          base_intellect: 10,
          base_spirit: 10,
          base_health: 50,
          base_mana: 0,
          min_damage: 1.0,
          max_damage: 2.0,
          base_attack_time: 2000,
          offhand_attack_time: 2000
        },
        player: %Player{skills: %{43 => Skills.new_entry(:level, false, 1), 415 => Skills.new_entry(:mono, false, 1)}},
        internal: %Internal{}
      }

      stats = %Stats{
        race: 1,
        class: 1,
        level: 6,
        strength: 12,
        agility: 12,
        stamina: 12,
        intellect: 12,
        spirit: 12,
        base_health: 100,
        base_mana: 0,
        next_level_xp: 100
      }

      character = Stats.apply(character, stats)

      assert character.player.skills[43].max == 30
      assert character.player.skills[43].value == 1
      assert character.player.skills[415] == Skills.new_entry(:mono, false, 1)

      character = Stats.apply(character, %{stats | level: 12})
      assert character.player.character_points1 == 3
    end
  end

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
