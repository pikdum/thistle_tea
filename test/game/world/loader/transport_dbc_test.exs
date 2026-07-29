defmodule ThistleTea.Game.World.Loader.TransportDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Transport

  @moduletag :dbc_db

  describe "load_taxi_path_nodes/1" do
    test "loads ordered ship waypoints" do
      nodes = Transport.load_taxi_path_nodes([302]) |> Map.fetch!(302)

      assert length(nodes) == 36
      assert Enum.map(nodes, & &1.node_index) == Enum.to_list(0..35)
      assert nodes |> Enum.map(& &1.map_id) |> Enum.uniq() |> Enum.sort() == [0, 1]
    end
  end

  describe "load_animation_routes/1" do
    test "loads the Deeprun Tram animation cycle" do
      [route] = Transport.load_animation_routes([176_080])

      assert route.kind == :animation
      assert route.period_ms == 143_333
      assert length(route.animation_frames) == 53
    end
  end
end
