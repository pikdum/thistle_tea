defmodule ThistleTea.Game.World.WorldPositionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpatialHash

  describe "position/2" do
    test "falls back to the spatial hash entry without published movement" do
      SpatialHash.update(:mobs, 901, 0, 1.0, 2.0, 3.0)
      on_exit(fn -> SpatialHash.remove(:mobs, 901) end)

      assert World.position(901) == {0, 1.0, 2.0, 3.0}
    end

    test "interpolates along published movement at the given time" do
      SpatialHash.update(:mobs, 902, 0, 0.0, 0.0, 0.0)
      SpatialHash.put_movement(902, {0, {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 1_000})
      on_exit(fn -> SpatialHash.remove(:mobs, 902) end)

      assert World.position(902, 1_500) == {0, 5.0, 0.0, 0.0}
    end

    test "returns the destination once the published movement has expired" do
      SpatialHash.update(:mobs, 903, 0, 0.0, 0.0, 0.0)
      SpatialHash.put_movement(903, {0, {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 1_000})
      on_exit(fn -> SpatialHash.remove(:mobs, 903) end)

      assert World.position(903, 99_000) == {0, 10.0, 0.0, 0.0}
    end
  end

  describe "nearby_units_exact/5" do
    test "includes moving units by their interpolated position" do
      SpatialHash.update(:mobs, 904, 0, 14.0, 0.0, 0.0)
      SpatialHash.put_movement(904, {0, {14.0, 0.0, 0.0}, [{0.0, 0.0, 0.0}], 1_000, 1_000})
      on_exit(fn -> SpatialHash.remove(:mobs, 904) end)

      assert World.nearby_units_exact(:mobs, 0, {0.0, 0.0, 0.0}, 10.0, 2_000) == [{904, 0.0}]
    end

    test "includes moving units whose stale position drifted within a spatial cell" do
      SpatialHash.update(:mobs, 906, 0, 120.0, 0.0, 0.0)
      SpatialHash.put_movement(906, {0, {120.0, 0.0, 0.0}, [{0.0, 0.0, 0.0}], 1_000, 1_000})
      on_exit(fn -> SpatialHash.remove(:mobs, 906) end)

      assert World.nearby_units_exact(:mobs, 0, {0.0, 0.0, 0.0}, 10.0, 2_000) == [{906, 0.0}]
    end

    test "excludes units whose interpolated position left the radius" do
      SpatialHash.update(:mobs, 905, 0, 0.0, 0.0, 0.0)
      SpatialHash.put_movement(905, {0, {0.0, 0.0, 0.0}, [{100.0, 0.0, 0.0}], 1_000, 1_000})
      on_exit(fn -> SpatialHash.remove(:mobs, 905) end)

      assert World.nearby_units_exact(:mobs, 0, {0.0, 0.0, 0.0}, 10.0, 2_000) == []
    end
  end
end
