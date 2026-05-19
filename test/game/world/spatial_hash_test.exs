defmodule ThistleTea.Game.World.SpatialHashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.SpatialHash

  describe "setup_tables/0" do
    test "creates read and write concurrent lookup tables" do
      for table <- [:players, :mobs, :game_objects, :entities] do
        assert :ets.info(table, :read_concurrency) == true
        assert :ets.info(table, :write_concurrency) == :auto
      end
    end
  end

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

  describe "query/6" do
    test "uses 2d cells and keeps 3d distance filtering" do
      table = :"spatial_hash_test_#{System.unique_integer([:positive])}"
      :ets.new(table, [:named_table, :public, :duplicate_bag])

      near_guid = System.unique_integer([:positive])
      high_guid = System.unique_integer([:positive])

      try do
        SpatialHash.insert(table, near_guid, 0, 0, 0, 0)
        SpatialHash.insert(table, high_guid, 0, 0, 0, 1_000)

        assert [{^near_guid, distance}] = SpatialHash.query(table, 0, 0, 0, 0, 10)
        assert distance == 0.0
      after
        SpatialHash.remove(table, near_guid)
        SpatialHash.remove(table, high_guid)
        :ets.delete(table)
      end
    end
  end

  describe "cell/4" do
    test "assigns negative coordinates to the previous cell" do
      assert SpatialHash.cell(0, -1, -1, 0) == {0, -1, -1}
    end
  end

  describe "cell_bounds/1" do
    test "calculates cell boundaries for origin cell" do
      bounds = SpatialHash.cell_bounds({0, 0, 0})
      assert bounds == {{-0.5, 124.5}, {-0.5, 124.5}}
    end

    test "calculates cell boundaries for positive cell" do
      bounds = SpatialHash.cell_bounds({0, 1, 2})
      assert bounds == {{124.5, 249.5}, {249.5, 374.5}}
    end

    test "calculates cell boundaries for negative cell" do
      bounds = SpatialHash.cell_bounds({0, -1, -1})
      assert bounds == {{-125.5, -0.5}, {-125.5, -0.5}}
    end
  end
end
