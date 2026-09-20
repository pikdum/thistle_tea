defmodule ThistleTea.Game.World.Loader.PetTrainingDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.DBC.CreatureFamily
  alias ThistleTea.Game.World.Loader.PetTraining

  @moduletag :dbc_db

  describe "vanilla training columns" do
    test "reads family skills, training costs, and rank successors" do
      assert %{training_skill: 208, secondary_skill: 270, pet_food_mask: 1} = DBC.get(CreatureFamily, 1)
      rows = DBC.all(from(ability in SkillLineAbility, where: ability.spell in [4187, 4188, 2649]))
      assert Enum.find(rows, &(&1.spell == 4187)).training_points == 5
      assert Enum.find(rows, &(&1.spell == 4187)).superseded_by == 4188
      assert Enum.find(rows, &(&1.spell == 4188)).training_points == 10
      assert Enum.find(rows, &(&1.spell == 2649)).training_points == 0
    end

    test "caches intrinsic wolf passives separately from trainable abilities" do
      table = PetTraining.init(__MODULE__)
      assert :ok = PetTraining.load_all(table)

      assert PetTraining.family_passives(1, table) |> Map.keys() |> Enum.sort() ==
               [8875, 17_223, 19_580, 19_581, 19_582, 19_589, 19_591, 20_782, 20_784]

      refute Map.has_key?(PetTraining.family_passives(1, table), 4187)
      assert PetTraining.abilities(table)[4187].cost == 5
    end
  end
end
