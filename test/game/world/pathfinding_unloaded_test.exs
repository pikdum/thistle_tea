defmodule ThistleTea.Game.World.PathfindingUnloadedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Test.Unique

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

  describe "get_zone_and_area/2" do
    test "names a single-zone map's zone where there is no area data" do
      map_id = 100_000 + Unique.integer()
      zone = Unique.integer()
      :ets.insert(Exploration, {{:map_zones, map_id}, [zone]})
      on_exit(fn -> :ets.delete(Exploration, {:map_zones, map_id}) end)

      assert Pathfinding.get_zone_and_area(map_id, {1.0, 2.0, 3.0}) == {zone, zone}
    end

    test "knows no zone for a map with several" do
      map_id = 100_000 + Unique.integer()
      :ets.insert(Exploration, {{:map_zones, map_id}, [Unique.integer(), Unique.integer()]})
      on_exit(fn -> :ets.delete(Exploration, {:map_zones, map_id}) end)

      assert Pathfinding.get_zone_and_area(map_id, {1.0, 2.0, 3.0}) == nil
    end
  end
end
