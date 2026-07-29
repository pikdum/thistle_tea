defmodule ThistleTea.Game.Entity.Server.TransportTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

  describe "route ownership" do
    test "publishes and advances an authoritative ship pose" do
      entry = :erlang.unique_integer([:positive])
      route = TransportLogic.build_ship(entry, "Test Ship", 10, ship_nodes(), 10, 1, 20_000)
      entity = GameObject.build_transport(template(entry), TransportLogic.pose_at(route, 0))
      clock = fn -> 1_000 end

      {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: clock})
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, initial} = Entity.call(entity.object.guid, :transport_info)
      assert initial.progress_ms == 0
      assert initial.world == WorldRef.open(0)

      assert {:ok, advanced} = Transports.advance(entity.object.guid, 3_000)
      assert advanced.progress_ms == 3_000
      assert elem(advanced.position, 0) > 0.0

      world = WorldRef.open(0)
      assert {^world, x, _y, _z} = World.position(entity.object.guid)
      assert_in_delta x, elem(advanced.position, 0), 0.000001
      assert Transports.get(entity.object.guid).progress_ms == 3_000
    end
  end

  describe "passenger ownership" do
    test "validates boarding, derives world coordinates, and tracks departure" do
      {entity, route, pid} = start_transport()
      player_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(player_guid)
      on_exit(fn -> Entity.unregister(player_guid) end)

      local_position = {2.0, 3.0, 4.0, 0.5}
      movement_block = passenger_movement(entity.object.guid, local_position)
      character = passenger(player_guid)

      assert {:ok, attached} = Transports.reconcile(character, movement_block)

      expected = TransportLogic.passenger_world_position(local_position, route_pose(route, 0))
      assert_tuple_in_delta(attached.position, expected)
      assert {:ok, %{passenger_count: 1}} = Entity.call(entity.object.guid, :transport_info)
      assert Transports.get(entity.object.guid).passenger_count == 1

      assert {:ok, _transport} = Transports.advance(entity.object.guid, 3_000)
      assert_receive {:transport_pose, %{guid: guid, passenger_count: 1}}
      assert guid == entity.object.guid

      assert {:ok, detached} =
               Transports.reconcile(%{character | movement_block: attached}, %MovementBlock{transport_guid: nil})

      assert detached.transport_guid == nil
      assert {:ok, %{passenger_count: 0}} = Entity.call(entity.object.guid, :transport_info)
      assert Transports.get(entity.object.guid).passenger_count == 0

      GenServer.stop(pid)
    end

    test "rejects out-of-bounds local coordinates without boarding" do
      {entity, _route, pid} = start_transport()
      player_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(player_guid)
      on_exit(fn -> Entity.unregister(player_guid) end)

      movement_block = passenger_movement(entity.object.guid, {251.0, 0.0, 0.0, 0.0})

      assert Transports.reconcile(passenger(player_guid), movement_block) == {:error, :invalid_transport}
      assert {:ok, %{passenger_count: 0}} = Entity.call(entity.object.guid, :transport_info)

      GenServer.stop(pid)
    end

    test "moves attached players with the transport across maps" do
      entry = :erlang.unique_integer([:positive])
      route = TransportLogic.build_ship(entry, "Test Ship", 10, cross_map_nodes(), 10, 1, 60_000)
      entity = GameObject.build_transport(template(entry), TransportLogic.pose_at(route, 0))
      {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: fn -> 1_000 end})
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      player_guid = :erlang.unique_integer([:positive])
      {:ok, _owner} = Entity.register(player_guid)
      on_exit(fn -> Entity.unregister(player_guid) end)

      movement_block = passenger_movement(entity.object.guid, {1.0, 2.0, 3.0, 0.25})
      assert {:ok, _attached} = Transports.reconcile(passenger(player_guid), movement_block)

      destination_frame = Enum.find(route.keyframes, &(&1.map_id == 1))
      assert {:ok, %{world: destination}} = Transports.advance(entity.object.guid, destination_frame.arrive_at_ms)
      assert destination == WorldRef.open(1)
      assert_receive {:transport_pose, %{world: ^destination}}
    end
  end

  defp start_transport do
    entry = :erlang.unique_integer([:positive])
    route = TransportLogic.build_ship(entry, "Test Ship", 10, ship_nodes(), 10, 1, 20_000)
    entity = GameObject.build_transport(template(entry), TransportLogic.pose_at(route, 0))
    clock = fn -> 1_000 end
    {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: clock})
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {entity, route, pid}
  end

  defp passenger(guid) do
    %Character{
      object: %{guid: guid},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp passenger_movement(transport_guid, local_position) do
    %MovementBlock{
      movement_flags: 0x02000000,
      position: {0.0, 0.0, 0.0, 0.0},
      transport_guid: transport_guid,
      transport_position: local_position
    }
  end

  defp route_pose(route, elapsed_ms) do
    TransportLogic.pose_at(route, elapsed_ms).position
  end

  defp template(entry) do
    %GameObjectTemplate{
      entry: entry,
      type: 15,
      display_id: 3015,
      name: "Test Ship",
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [10, 10, 1] ++ List.duplicate(0, 21)
    }
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

  defp cross_map_nodes do
    [
      node(0, {-10.0, 0.0, 0.0}, 0, 0, 0),
      node(1, {0.0, 0.0, 0.0}, 2, 2, 0),
      node(2, {10.0, 0.0, 0.0}, 0, 0, 0),
      node(3, {20.0, 0.0, 0.0}, 0, 0, 0),
      node(4, {30.0, 0.0, 0.0}, 0, 0, 1),
      node(5, {40.0, 0.0, 0.0}, 0, 0, 1),
      node(6, {50.0, 0.0, 0.0}, 2, 2, 1),
      node(7, {60.0, 0.0, 0.0}, 0, 0, 1)
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
