defmodule ThistleTea.Game.Entity.Logic.CombatRatingsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.CombatRatings

  @warrior 1
  @rogue 4
  @mage 8

  describe "melee_crit_chance/3" do
    test "warriors get one percent crit per 3.9 agility at level 1" do
      assert_in_delta CombatRatings.melee_crit_chance(@warrior, 1, 39), 10.0, 0.001
    end

    test "warriors need 20 agility per percent at level 60" do
      assert_in_delta CombatRatings.melee_crit_chance(@warrior, 60, 100), 5.0, 0.001
    end

    test "mages add their class base crit" do
      assert_in_delta CombatRatings.melee_crit_chance(@mage, 60, 20), 3.2 + 1.0, 0.001
    end
  end

  describe "dodge_chance/3" do
    test "rogues dodge cheaply from agility" do
      assert_in_delta CombatRatings.dodge_chance(@rogue, 60, 145), 10.0, 0.001
    end

    test "classes without base bonus have zero dodge at zero agility" do
      assert CombatRatings.dodge_chance(@warrior, 30, 0) == 0.0
    end
  end

  describe "parry_chance/1" do
    test "parry classes parry at five percent" do
      assert CombatRatings.parry_chance(@warrior) == 5.0
      assert CombatRatings.parry_chance(@rogue) == 5.0
    end

    test "mages cannot parry" do
      assert CombatRatings.parry_chance(@mage) == 0.0
    end
  end

  describe "block_chance/1 and block_value/2" do
    test "an equipped shield enables blocking" do
      assert CombatRatings.block_chance(%{shields: 1}) == 5.0
      assert CombatRatings.block_chance(%{shields: 0}) == 0.0
      assert CombatRatings.block_chance(%{}) == 0.0
    end

    test "block value adds strength over twenty" do
      assert CombatRatings.block_value(%{shield_block: 20}, 40) == 21
      assert CombatRatings.block_value(%{}, 40) == 1
      assert CombatRatings.block_value(%{}, 0) == 0
    end
  end

  describe "sync/1" do
    test "writes the derived percentages to the player component" do
      character = %Character{
        unit: %Unit{class: @warrior, level: 60, agility: 100, equipment_bonuses: %{shields: 1, shield_block: 20}},
        player: %Player{}
      }

      character = CombatRatings.sync(character)

      assert_in_delta character.player.crit_percentage, 5.0, 0.001
      assert_in_delta character.player.dodge_percentage, 5.0, 0.001
      assert character.player.parry_percentage == 5.0
      assert character.player.block_percentage == 5.0
    end

    test "leaves non-player entities untouched" do
      entity = %{unit: %Unit{}}

      assert CombatRatings.sync(entity) == entity
    end
  end
end
