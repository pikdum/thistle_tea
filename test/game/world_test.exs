defmodule ThistleTea.Game.WorldTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.EntitySupervisor
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

  defp start_tracked_transport(guid, world) do
    assert EntityRegistry.whereis(guid) == nil
    {:ok, pid} = EntitySupervisor.start_child(guid, {EntityProcess, guid})
    SpatialHash.insert(:game_objects, guid, world, 0.0, 0.0, 0.0)
    pid
  end
end
