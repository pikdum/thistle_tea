defmodule ThistleTea.Game.World.PathfindingUnloadedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Pathfinding

  @unloaded_map 9_999

  describe "find_path/4" do
    test "walks straight to the destination on a map without a navigation mesh" do
      assert Pathfinding.find_path(@unloaded_map, {0.0, 0.0, 0.0}, {5.0, 6.0, 1.0}) == [{5.0, 6.0, 1.0}]
    end

    test "flies straight too" do
      assert Pathfinding.find_path(@unloaded_map, {0.0, 0.0, 0.0}, {5.0, 6.0, 9.0}, flying?: true) == [
               {5.0, 6.0, 9.0}
             ]
    end
  end
end
