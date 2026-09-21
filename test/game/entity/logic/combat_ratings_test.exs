defmodule ThistleTea.Game.Entity.Logic.CombatRatingsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

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

  describe "spell_crit_chance/3" do
    test "uses the VMangos class intellect formula" do
      assert_in_delta CombatRatings.spell_crit_chance(@mage, 60, 100), 5.559, 0.001
    end

    test "non-caster classes do not gain spell crit from intellect" do
      assert CombatRatings.spell_crit_chance(@warrior, 60, 100) == 0.0
    end
  end

  describe "parry_chance/1" do
    test "learned parry requires a usable weapon" do
      character = trained_character()
      assert CombatRatings.parry_chance(character) == 5.0
      assert CombatRatings.parry_chance(%{character | player: %Player{}}) == 0.0
    end

    test "class alone does not grant parry" do
      character = trained_character()

      for class <- [@warrior, @rogue, 7, @mage] do
        untrained = %{character | unit: %{character.unit | class: class}, internal: %Internal{}}
        assert CombatRatings.parry_chance(untrained) == 0.0
      end
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
      character = trained_character() |> CombatRatings.sync()

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

  defp trained_character do
    %Character{
      unit: %Unit{class: @warrior, level: 60, agility: 100, equipment_bonuses: %{shields: 1, shield_block: 20}},
      player: %Player{visible_item_16_0: 1},
      internal: %Internal{
        spellbook: %{
          107 => %Spell{id: 107, effects: [%Effect{type: :block}]},
          3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}
        }
      }
    }
  end
end
