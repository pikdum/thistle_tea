defmodule ThistleTea.Game.World.PathfindingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  @human_start {-8949.95, -132.49, 83.53}

  describe "line_of_sight?/3" do
    test "open air is visible" do
      assert Pathfinding.line_of_sight?(0, @human_start, {-8955.0, -140.0, 84.0})
    end

    test "Northshire Abbey blocks the ray" do
      refute Pathfinding.line_of_sight?(0, @human_start, {-8914.0, -164.0, 82.0})
    end

    test "a ray through the abbey to the far side is blocked" do
      refute Pathfinding.line_of_sight?(0, @human_start, {-8880.0, -180.0, 82.0})
    end

    test "an unloaded map fails open" do
      assert Pathfinding.line_of_sight?(999, {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0})
    end

    test "serves concurrent rays from a loaded ADT" do
      results =
        1..200
        |> Task.async_stream(
          fn _ -> Pathfinding.line_of_sight?(0, @human_start, {-8955.0, -140.0, 84.0}) end,
          max_concurrency: 20,
          ordered: false
        )
        |> Enum.to_list()

      assert Enum.all?(results, &(&1 == {:ok, true}))
    end
  end

  describe "find_path/4" do
    test "routes from overlapping Deadmines surfaces" do
      cases = [
        {{-192.036893, -592.948152, 39.148481}, {-123.865125, -607.068945, 16.866046}},
        {{-191.786904, -592.680173, 39.258589}, {-126.667646, -594.773328, 19.114894}},
        {{-191.963134, -592.855987, 39.210442}, {-127.230821, -594.357885, 19.099384}},
        {{-192.036893, -592.948152, 38.747131}, {-123.865125, -607.068945, 16.866046}}
      ]

      for {start, destination} <- cases, steep <- [false, true] do
        assert [_ | _] = path = Pathfinding.find_path(36, start, destination, allow_steep: steep)
        assert distance(List.last(path), destination) < 1.5
      end
    end

    test "keeps chasing after crossing a Deadmines surface overlap" do
      start = {-192.036893, -592.948152, 38.747131}
      destination = {-123.865125, -607.068945, 16.866046}

      final =
        Enum.reduce_while(1..600, start, fn _, position ->
          if distance(position, destination) < 1.5 do
            {:halt, position}
          else
            assert [next | _] = Pathfinding.find_path(36, position, destination, allow_steep: true)
            assert distance(position, next) > 0.0001
            {:cont, advance(position, next, 0.3)}
          end
        end)

      assert distance(final, destination) < 1.5
    end

    test "preserves routes where the closest overlapping surface is disconnected" do
      start = {-120.521146, -405.568710, 59.121227}
      destination = {-127.230821, -594.357885, 19.099384}
      assert [_ | _] = path = Pathfinding.find_path(36, start, destination, allow_steep: true)
      assert distance(List.last(path), destination) < 1.5
    end

    test "preserves routes through RFC and the Elwynn mines" do
      cases = [
        {389, {-376.811, 209.224, -21.801}, {-244.743, 150.085, -18.7494}},
        {0, {-8671.72, -124.325, 92.6409}, {-8766.6, -156.686, 82.4446}},
        {0, {-9796.72, 131.134, 24.4699}, {-9954.19, 221.055, 26.0012}},
        {0, {-9326.82, -713.03, 67.5269}, {-9088.73, -573.684, 62.5813}}
      ]

      for {map, start, destination} <- cases, steep <- [false, true] do
        assert [_ | _] = path = Pathfinding.find_path(map, start, destination, allow_steep: steep)
        assert distance(List.last(path), destination) < 1.5
      end
    end

    test "routes the Deadmines alarm pirates to the breached door" do
      destination = {-99.6611, -671.071655, 7.42241}

      for start <- [{-102.521, -697.942, 8.84454}, {-89.7001, -691.332, 8.24514}] do
        path = Pathfinding.find_path(36, start, destination, allow_steep: true)
        assert is_list(path) and path != []
        {x, y, z} = List.last(path)
        assert_in_delta x, elem(destination, 0), 1.0
        assert_in_delta y, elem(destination, 1), 1.0
        assert_in_delta z, elem(destination, 2), 1.0
      end
    end

    test "routes the gunpowder ambush into the corridor" do
      path =
        Pathfinding.find_path(36, {-131.290833, -591.243103, 18.077190}, {-115.263672, -617.396118, 13.579387},
          allow_steep: true
        )

      assert is_list(path) and path != []
    end

    test "finds a path on player-walkable ground" do
      path = Pathfinding.find_path(0, @human_start, {-8955.0, -140.0, 84.0})
      assert is_list(path) and path != []
    end

    test "steep-permitted pathing succeeds where strict pathing does" do
      path = Pathfinding.find_path(0, @human_start, {-8955.0, -140.0, 84.0}, allow_steep: true)
      assert is_list(path) and path != []
    end
  end

  describe "snap_to_ground/2" do
    test "drops a mid-jump position back onto the terrain" do
      {x, y, z} = @human_start
      assert {^x, ^y, snapped} = Pathfinding.snap_to_ground(0, {x, y, z + 4.0})
      assert_in_delta snapped, z, 0.5
    end

    test "keeps the position on an unloaded map" do
      assert Pathfinding.snap_to_ground(999, {0.0, 0.0, 5.0}) == {0.0, 0.0, 5.0}
    end
  end

  describe "query_liquid_surface/2" do
    test "returns the liquid surface at a fishing-hole coordinate" do
      assert_in_delta Pathfinding.query_liquid_surface(0, {-2183.26, -1867.59, 0.0}), 0.268, 0.01
    end

    test "places a fishing cast on the queried liquid surface" do
      character = %{
        internal: %{world: %WorldRef{map_id: 0}},
        movement_block: %{position: {-2198.26, -1867.59, 0.0, 0.0}}
      }

      assert {x, y, z, orientation} = Fishing.cast_position(character, fn -> 0.5 end)
      assert_in_delta x, -2183.26, 0.01
      assert_in_delta y, -1867.59, 0.01
      assert_in_delta z, 0.268, 0.01
      assert_in_delta orientation, 0.0, 0.001
    end
  end

  defp distance({ax, ay, az}, {bx, by, bz}) do
    :math.sqrt((ax - bx) ** 2 + (ay - by) ** 2 + (az - bz) ** 2)
  end

  defp advance({ax, ay, az} = start, {bx, by, bz} = target, amount) do
    ratio = min(1.0, amount / distance(start, target))
    {ax + (bx - ax) * ratio, ay + (by - ay) * ratio, az + (bz - az) * ratio}
  end
end
