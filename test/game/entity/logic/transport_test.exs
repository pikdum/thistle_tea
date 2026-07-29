defmodule ThistleTea.Game.Entity.Logic.TransportTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Transport

  describe "build_ship/7" do
    test "builds stop timing and honors the VMangos period override" do
      route = Transport.build_ship(1, "Test", 10, ship_nodes(), 10, 1, 20_000)

      assert route.kind == :ship
      assert route.period_ms == 20_000
      assert route.maps == MapSet.new([0])
      assert hd(route.keyframes).depart_at_ms == 2_000
      assert List.last(route.keyframes).depart_at_ms == 20_000
    end

    test "marks the frame before a map discontinuity for teleportation" do
      nodes =
        [
          node(0, {-10.0, 0.0, 0.0}, 0, 0),
          node(1, {0.0, 0.0, 0.0}, 2, 2),
          node(2, {10.0, 0.0, 0.0}, 0, 0),
          node(3, {20.0, 0.0, 0.0}, 0, 0),
          node(4, {30.0, 0.0, 0.0}, 0, 0, 1),
          node(5, {40.0, 0.0, 0.0}, 0, 0, 1),
          node(6, {50.0, 0.0, 0.0}, 2, 2, 1),
          node(7, {60.0, 0.0, 0.0}, 0, 0, 1)
        ]

      route = Transport.build_ship(1, "Test", 10, nodes, 10, 1, 20_000)

      assert Enum.any?(route.keyframes, & &1.teleport?)
      assert route.maps == MapSet.new([0, 1])
    end
  end

  describe "pose_at/2" do
    test "holds a ship at a stop until departure" do
      route = Transport.build_ship(1, "Test", 10, ship_nodes(), 10, 1, 20_000)

      pose = Transport.pose_at(route, 1_000)

      assert pose.position == {0.0, 0.0, 0.0, :math.pi()}
      refute pose.moving?
    end

    test "moves a ship along its spline after departure" do
      route = Transport.build_ship(1, "Test", 10, ship_nodes(), 10, 1, 20_000)

      pose = Transport.pose_at(route, 3_000)

      assert pose.moving?
      assert elem(pose.position, 0) > 0.0
      assert elem(pose.position, 0) < 20.0
    end
  end

  describe "pose_at/4" do
    test "interpolates and rotates local transport animation" do
      route =
        Transport.build_animation(10, "Elevator", [
          %{time_ms: 0, position: {0.0, 0.0, 0.0}, sequence: 0},
          %{time_ms: 1_000, position: {10.0, 0.0, 4.0}, sequence: 0}
        ])

      pose = Transport.pose_at(route, 500, {100.0, 200.0, 300.0, 1.5}, {0.0, 0.0, 0.0, 1.0})

      assert pose.position == {105.0, 200.0, 302.0, 1.5}
      assert pose.moving?
    end
  end

  describe "passenger coordinate transforms" do
    test "round trips between local and world positions" do
      transport_position = {100.0, 200.0, 30.0, 0.75}
      local_position = {4.0, -2.0, 3.0, 1.25}

      world_position = Transport.passenger_world_position(local_position, transport_position)
      restored = Transport.passenger_local_position(world_position, transport_position)

      assert_tuple_in_delta(restored, local_position)
    end
  end

  defp ship_nodes do
    [
      node(0, {-10.0, 0.0, 0.0}, 0, 0),
      node(1, {0.0, 0.0, 0.0}, 2, 2),
      node(2, {10.0, 0.0, 0.0}, 0, 0),
      node(3, {20.0, 0.0, 0.0}, 2, 2),
      node(4, {10.0, 0.0, 0.0}, 0, 0),
      node(5, {0.0, 0.0, 0.0}, 2, 2)
    ]
  end

  defp node(index, position, flags, delay) do
    node(index, position, flags, delay, 0)
  end

  defp node(index, position, flags, delay, map_id) do
    %{node_index: index, map_id: map_id, position: position, flags: flags, delay: delay}
  end

  defp assert_tuple_in_delta(actual, expected) do
    actual
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(expected))
    |> Enum.each(fn {actual_value, expected_value} ->
      assert_in_delta actual_value, expected_value, 0.000001
    end)
  end
end
