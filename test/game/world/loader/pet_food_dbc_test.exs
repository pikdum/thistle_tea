defmodule ThistleTea.Game.World.Loader.PetFoodDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.DBC.CreatureFamily
  alias ThistleTea.Game.Entity.Logic.Hunter

  @moduletag :dbc_db

  describe "get/2" do
    test "reads diets rather than skill ids from vanilla creature families" do
      for {family, foods} <- [{1, [1]}, {2, [1, 2]}, {4, [1, 2, 3, 4, 5, 6]}, {8, [2, 4, 5, 6]}, {9, [5, 6]}] do
        mask = DBC.get(CreatureFamily, family).pet_food_mask
        assert Enum.filter(1..8, &Hunter.food_allowed?(mask, &1)) == foods
      end
    end
  end
end
