defmodule ThistleTea.Game.World.Loader.PetTrainingDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.DBC.CreatureFamily

  @moduletag :dbc_db

  describe "vanilla training columns" do
    test "reads family skills, training costs, and rank successors" do
      assert %{training_skill: 208, pet_food_mask: 1} = DBC.get(CreatureFamily, 1)
      rows = DBC.all(from(ability in SkillLineAbility, where: ability.spell in [4187, 4188, 2649]))
      assert Enum.find(rows, &(&1.spell == 4187)).training_points == 5
      assert Enum.find(rows, &(&1.spell == 4187)).superseded_by == 4188
      assert Enum.find(rows, &(&1.spell == 4188)).training_points == 10
      assert Enum.find(rows, &(&1.spell == 2649)).training_points == 0
    end
  end
end
