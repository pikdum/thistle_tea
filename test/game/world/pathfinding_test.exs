defmodule ThistleTea.Game.World.PathfindingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Pathfinding.Aquatic
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  @human_start {-8949.95, -132.49, 83.53}

  describe "find_path/4 with aquatic habitats" do
    test "retains depth and follows vertical destinations in open water" do
      origin = {-2183.26, -1867.59, -5.0}
      opts = [can_walk?: false, can_swim?: true, swim_animation?: true]

      for destination <- [{-2178.26, -1867.59, -3.0}, {-2183.26, -1867.59, -1.0}] do
        assert Pathfinding.find_path(0, origin, destination, opts) == [destination]
      end
    end

    test "clamps nearby airborne targets to the water surface and rejects dry destinations" do
      origin = {-2183.26, -1867.59, -5.0}
      opts = [can_walk?: false, can_swim?: true, swim_animation?: true]
      assert [{x, y, z}] = Pathfinding.find_path(0, origin, {-2183.26, -1867.59, 1.0}, opts)
      assert {x, y} == {-2183.26, -1867.59}
      assert_in_delta z, 0.268179, 0.00001
      assert Pathfinding.find_path(0, origin, {-2183.26, -1867.59, 5.0}, opts) == nil
      assert Pathfinding.find_path(0, origin, @human_start, opts) == nil
    end

    test "land-only creatures reject submerged targets and water needs enough depth" do
      origin = {-2183.26, -1867.59, -5.0}
      assert Pathfinding.find_path(0, origin, {-2178.26, -1867.59, -3.0}, can_walk?: true, can_swim?: false) == nil
      assert Aquatic.water(0, origin, 5.0)
      assert Aquatic.water(0, origin, 20.0) == nil
      assert Aquatic.water(0, {-2183.26, -1867.59, -20.0}) == nil
    end

    test "underwater wandering retains depth instead of choosing the seabed" do
      origin = {-2183.26, -1867.59, -5.0}
      opts = [can_walk?: false, can_swim?: true, swim_animation?: true]

      for _ <- 1..12 do
        assert {x, y, z} = Aquatic.random_point(0, origin, 2.0, opts)
        assert_in_delta z, -5.0, 0.00001
        assert distance(origin, {x, y, z}) <= 2.0
        assert Aquatic.water(0, {x, y, z})
      end
    end

    test "rejects a detour that takes a water-only creature above the surface" do
      origin = {-2183.26, -1867.59, -5.0}
      destination = {-2178.26, -1867.59, -3.0}
      opts = [can_walk?: false, can_swim?: true, swim_animation?: false]
      detour = fn _, _, _, _ -> [{-2183.26, -1867.59, 5.0}, destination] end
      assert Aquatic.path(0, origin, destination, opts, detour) == nil
    end
  end

  describe "find_path/4 with flight" do
    test "retains a flight destination above the ground mesh" do
      origin = {-8949.95, -132.49, 110.0}
      destination = {-8969.95, -132.49, 120.0}
      assert Pathfinding.find_path(0, origin, destination, flying?: true) == [destination]
    end

    test "does not fly straight through an obstructing wall" do
      origin = {-8930.0, -150.0, 84.0}
      destination = {-8910.0, -150.0, 84.0}
      path = Pathfinding.find_path(0, origin, destination, flying?: true)
      refute path == [destination]

      if is_list(path) do
        for [start, stop] <- Enum.chunk_every([origin | path], 2, 1, :discard) do
          assert Pathfinding.collision_position(0, start, stop) == stop
        end
      end
    end
  end

  describe "find_random_point_around_circle/3" do
    test "bounds small-radius samples inside large navigation polygons" do
      anchor = {16_479.2, 16_468.1, 69.43277740478516}

      points = for _ <- 1..30, do: Pathfinding.find_random_point_around_circle(451, anchor, 2.0)
      assert Enum.count(points, &is_tuple/1) >= 20

      for {x, y, z} <- points do
        assert distance({x, y, 0.0}, {elem(anchor, 0), elem(anchor, 1), 0.0}) <= 2.01
        assert abs(z - elem(anchor, 2)) < 1.0
        assert Pathfinding.line_of_sight?(451, anchor, {x, y, z})
      end
    end

    test "accepts an integer script radius" do
      assert {x, y, z} = Pathfinding.find_random_point_around_circle(0, @human_start, 5)
      assert is_float(x) and is_float(y) and is_float(z)
    end
  end

  describe "walk_hit_position/3" do
    test "stops at the abbey instead of routing around it" do
      origin = {-8930.0, -150.0, 82.0}
      destination = {-8910.0, -150.0, 82.0}
      assert {x, y, _z} = position = Pathfinding.walk_hit_position(0, origin, destination)
      assert_in_delta y, -150.0, 0.05
      assert x > elem(origin, 0)
      assert x < elem(destination, 0) - 1.0
      assert Pathfinding.line_of_sight?(0, origin, position)
    end

    test "retains the forward line where a detour would reverse direction" do
      origin = {-8930.0, -150.0, 82.0}
      angle = 13 * :math.pi() / 8
      destination = {-8930.0 + 20 * :math.cos(angle), -150.0 + 20 * :math.sin(angle), 82.0}
      assert {x, y, _z} = Pathfinding.walk_hit_position(0, origin, destination)
      assert (x + 8930.0) * :math.cos(angle) + (y + 150.0) * :math.sin(angle) > 0
      assert abs((x + 8930.0) * :math.sin(angle) - (y + 150.0) * :math.cos(angle)) < 0.05
    end

    test "covers the full distance on open ground" do
      assert {x, y, z} = Pathfinding.walk_hit_position(0, @human_start, {-8969.95, -132.49, 83.53})
      assert_in_delta x, -8969.95, 0.01
      assert_in_delta y, -132.49, 0.01
      assert abs(z - 83.53) < 2.0
    end

    test "rejects missing mesh and positions far above a floor" do
      assert Pathfinding.walk_hit_position(999, @human_start, {-8969.95, -132.49, 83.53}) == nil
      assert Pathfinding.walk_hit_position(0, {-8949.95, -132.49, 133.53}, {-8969.95, -132.49, 133.53}) == nil
    end
  end

  describe "first_collision_position/3" do
    test "clips a forward destination at the abbey wall" do
      destination = {-8914.0, -164.0, 82.0}
      position = Pathfinding.first_collision_position(0, @human_start, destination)
      assert Pathfinding.line_of_sight?(0, @human_start, position)
      assert distance(position, destination) > 5.0
      assert distance(position, @human_start) > 1.0
    end

    test "retains unobstructed horizontal coordinates and tolerates missing geometry" do
      assert {x, y, z} = Pathfinding.first_collision_position(0, @human_start, {-8955.0, -140.0, 84.0})
      assert {x, y} == {-8955.0, -140.0}
      assert abs(z - 84.0) < 2.0
      assert Pathfinding.first_collision_position(999, {0.0, 0.0, 0.0}, {5.0, 0.0, 0.0}) == {5.0, 0.0, 0.0}
    end
  end

  describe "collision_position/3" do
    test "clips the collision ray without snapping its height to the ground" do
      origin = {-8930.0, -150.0, 84.0}
      assert {x, y, z} = Pathfinding.collision_position(0, origin, {-8910.0, -150.0, 84.0})
      assert x > -8930.0 and x < -8911.0
      assert y == -150.0
      assert z == 84.0
    end

    test "retains an unobstructed airborne destination" do
      destination = {-8969.95, -132.49, 100.0}
      assert Pathfinding.collision_position(0, {-8949.95, -132.49, 100.0}, destination) == destination
    end
  end

  describe "get_zone_and_area/2" do
    test "retains the tower area on an unlabelled roof and in the air above it" do
      for z <- [192.51268, 194.6, 220.0] do
        assert Pathfinding.get_zone_and_area(0, {1854.0, -3724.0, z}) == {139, 2263}
      end
    end

    test "resolves Goldshire across the inn's unlabelled floor surface" do
      for z <- [56.96, 56.96255874633789, 57.05, 59.0] do
        assert Pathfinding.get_zone_and_area(0, {-9461.5, 16.190000534057617, z}) == {12, 87}
      end
    end

    test "does not invent an area when map geometry is unavailable" do
      assert Pathfinding.get_zone_and_area(999, {0.0, 0.0, 0.0}) == nil
    end

    test "rejects unsigned unknown-area sentinels on Programmer Isle" do
      for z <- [69.34, 69.5] do
        assert Pathfinding.get_zone_and_area(451, {16_335.2, 16_298.1, z}) == nil
      end

      assert Pathfinding.get_zone_and_area(451, {16_303.2, 16_318.1, 69.44}) == {22, 22}
    end
  end

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
