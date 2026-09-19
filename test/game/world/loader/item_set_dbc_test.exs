defmodule ThistleTea.Game.World.Loader.ItemSetDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ItemSet
  alias ThistleTea.Game.World.Loader.ItemSet, as: ItemSetLoader

  @moduletag :dbc_db

  describe "load_all/1" do
    test "loads all thresholds and profession requirements" do
      table = ItemSetLoader.init(__MODULE__)
      assert :ok = ItemSetLoader.load_all(table)

      assert %ItemSet{name: "The Gladiator", bonuses: [{2, 9761}, {3, 7514}, {4, 9140}, {5, 7597}]} =
               ItemSetLoader.get(1, table)

      assert %ItemSet{required_skill: 197, required_skill_rank: 300, bonuses: [{3, 18_382}]} =
               ItemSetLoader.get(421, table)

      assert ItemSetLoader.get(0, table) == nil
    end
  end
end
