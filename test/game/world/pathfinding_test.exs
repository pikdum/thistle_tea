defmodule ThistleTea.Game.World.PathfindingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Pathfinding

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
end
