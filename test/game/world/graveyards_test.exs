defmodule ThistleTea.Game.World.GraveyardsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Graveyards
  alias ThistleTea.Game.World.Loader.Graveyard

  describe "project/2" do
    test "disables the neutral seed and opens the closest graveyard only to its controller" do
      table = :ets.new(:controlled_graveyards, [:set])
      tower = %{id: 927, map: 0, position: {0.0, 0.0, 0.0}, faction: 0}
      fallback = %{id: 1, map: 0, position: {100.0, 0.0, 0.0}, faction: 0}
      seed = [tower, fallback]
      Graveyards.control(927, nil, table)
      assert Graveyards.project(seed, table) == [fallback]
      Graveyards.control(927, 469, table)
      controlled = Graveyards.project(seed, table)
      assert Graveyard.closest_of(controlled, 0, {1.0, 0.0, 0.0}, 469).id == 927
      assert Graveyard.closest_of(controlled, 0, {1.0, 0.0, 0.0}, 67).id == 1
      Graveyards.control(927, 67, table)
      controlled = Graveyards.project(seed, table)
      assert Graveyard.closest_of(controlled, 0, {1.0, 0.0, 0.0}, 67).id == 927
      assert Graveyard.closest_of(controlled, 0, {1.0, 0.0, 0.0}, 469).id == 1
      Graveyards.control(927, nil, table)
      assert Graveyards.project(seed, table) == [fallback]
    end
  end
end
