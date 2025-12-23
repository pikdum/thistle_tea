defmodule ThistleTea.Game.World.SpatialHashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.SpatialHash

  describe "distance/2" do
    test "calculates euclidean distance" do
      assert SpatialHash.distance({0, 0, 0}, {3, 4, 0}) == 5.0
      assert SpatialHash.distance({1, 2, 3}, {1, 2, 3}) == 0.0
    end

    test "handles negative coordinates" do
      dist = SpatialHash.distance({-3, -4, 0}, {0, 0, 0})
      assert_in_delta dist, 5.0, 0.001
    end

    test "calculates 3d distance" do
      dist = SpatialHash.distance({0, 0, 0}, {1, 1, 1})
      assert_in_delta dist, :math.sqrt(3), 0.001
    end
  end

  describe "cell_bounds/1" do
    test "calculates cell boundaries for origin cell" do
      bounds = SpatialHash.cell_bounds({0, 0, 0, 0})
      assert bounds == {{-0.5, 124.5}, {-0.5, 124.5}, {-0.5, 124.5}}
    end

    test "calculates cell boundaries for positive cell" do
      bounds = SpatialHash.cell_bounds({0, 1, 2, 3})
      assert bounds == {{124.5, 249.5}, {249.5, 374.5}, {374.5, 499.5}}
    end

    test "calculates cell boundaries for negative cell" do
      bounds = SpatialHash.cell_bounds({0, -1, -1, -1})
      assert bounds == {{-125.5, -0.5}, {-125.5, -0.5}, {-125.5, -0.5}}
    end
  end
end
