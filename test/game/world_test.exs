defmodule ThistleTea.Game.WorldTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  defmodule EntityProcess do
    @moduledoc false
    use GenServer

    alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

    def start_link(guid) do
      GenServer.start_link(__MODULE__, nil, name: EntityRegistry.via(guid))
    end

    @impl GenServer
    def init(state), do: {:ok, state}
  end

  describe "stop_world_entities/2" do
    test "keeps global transports and stops instanced transports" do
      open_world = WorldRef.open(0)
      instance_world = WorldRef.instance(47, System.unique_integer([:positive]))
      global_guid = Guid.runtime(:transport, 176_080)
      instance_guid = Guid.runtime(:transport, 176_081)
      global_pid = start_tracked_transport(global_guid, open_world)
      instance_pid = start_tracked_transport(instance_guid, instance_world)

      on_exit(fn ->
        if Process.alive?(global_pid), do: World.stop_entity(global_pid)
        if Process.alive?(instance_pid), do: World.stop_entity(instance_pid)
        SpatialHash.remove(:game_objects, global_guid)
        SpatialHash.remove(:game_objects, instance_guid)
      end)

      global_monitor = Process.monitor(global_pid)
      instance_monitor = Process.monitor(instance_pid)

      World.stop_world_entities(open_world)
      refute_receive {:DOWN, ^global_monitor, :process, ^global_pid, _reason}, 20
      assert Process.alive?(global_pid)

      World.stop_world_entities(instance_world)
      assert_receive {:DOWN, ^instance_monitor, :process, ^instance_pid, :shutdown}
    end
  end

  describe "spawn_guid/3" do
    test "resolves database identities inside the exact world copy" do
      db_guid = System.unique_integer([:positive, :monotonic])
      first_world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      second_world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      first_guid = Guid.runtime(:mob, 10_917)
      second_guid = Guid.runtime(:mob, 10_917)

      SpatialHash.insert(:mobs, first_guid, first_world, 1.0, 2.0, 3.0)
      SpatialHash.insert(:mobs, second_guid, second_world, 4.0, 5.0, 6.0)
      Metadata.put(first_guid, %{db_guid: db_guid})
      Metadata.put(second_guid, %{db_guid: db_guid})

      on_exit(fn ->
        SpatialHash.remove(:mobs, first_guid)
        SpatialHash.remove(:mobs, second_guid)
        Metadata.delete(first_guid)
        Metadata.delete(second_guid)
      end)

      assert World.spawn_guid(first_world, :mob, db_guid) == first_guid
      assert World.spawn_guid(second_world, :mob, db_guid) == second_guid
      assert World.spawn_guid(WorldRef.instance(329, -1), :mob, db_guid) == nil
    end
  end

  defp start_tracked_transport(guid, world) do
    assert EntityRegistry.whereis(guid) == nil
    {:ok, pid} = EntitySupervisor.start_child(guid, {EntityProcess, guid})
    SpatialHash.insert(:game_objects, guid, world, 0.0, 0.0, 0.0)
    pid
  end
end
