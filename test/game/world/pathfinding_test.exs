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
end
