defmodule ThistleTea.Game.World.SpawnPoolTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.WorldRef

  describe "singleton lifecycle" do
    test "recycles a persistent entity into a fresh process" do
      low_guid = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, 1, low_guid)
      group = {:singleton, :game_object, low_guid}
      key = {WorldRef.open(0), group}
      blueprint = game_object(guid)

      :ok = SpawnPool.activate(group, {WorldRef.open(0), 0, 0}, blueprint)
      first_pid = await_entity(guid)

      send(first_pid, :chest_respawn)
      second_pid = await_replacement(guid, first_pid)

      refute first_pid == second_pid

      Process.exit(second_pid, :kill)
      third_pid = await_replacement(guid, second_pid)

      refute second_pid == third_pid

      assert SpawnPool.status(key) == %{
               selected: MapSet.new([{:game_object, low_guid}]),
               running: [game_object: low_guid]
             }

      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, key)
      DynamicSupervisor.terminate_child(SpawnPool.Supervisor, pool_pid)
    end

    test "stops and restarts event-gated incarnations when eligibility changes" do
      low_guid = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, 1, low_guid)
      group = {:singleton, :game_object, low_guid}
      key = {WorldRef.open(0), group}
      blueprint = put_in(game_object(guid).internal.event, 42)

      :ok = SpawnPool.activate(group, {WorldRef.open(0), 0, 0}, blueprint)
      first_pid = await_entity(guid)

      SpawnPool.refresh_all([])
      await_absent(guid)

      SpawnPool.refresh_all([42])
      second_pid = await_replacement(guid, first_pid)

      refute first_pid == second_pid

      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, key)
      DynamicSupervisor.terminate_child(SpawnPool.Supervisor, pool_pid)
    end

    test "isolates and stops pools by world copy" do
      low_guid = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, 1, low_guid)
      group = {:singleton, :game_object, low_guid}
      first_world = WorldRef.instance(389, System.unique_integer([:positive]))
      second_world = WorldRef.instance(389, System.unique_integer([:positive]))
      first_key = {first_world, group}
      second_key = {second_world, group}
      blueprint = game_object(guid)

      :ok = SpawnPool.activate(group, {first_world, 0, 0}, blueprint)
      :ok = SpawnPool.activate(group, {second_world, 0, 0}, blueprint)

      assert [{first_pid, _value}] = Registry.lookup(SpawnPool.Registry, first_key)
      assert [{second_pid, _value}] = Registry.lookup(SpawnPool.Registry, second_key)
      refute first_pid == second_pid

      SpawnPool.stop_world(first_world)

      await_pool_absent(first_key)
      assert [{^second_pid, _value}] = Registry.lookup(SpawnPool.Registry, second_key)

      DynamicSupervisor.terminate_child(SpawnPool.Supervisor, second_pid)
    end
  end

  defp game_object(guid) do
    %GameObject{
      object: %Object{guid: guid, entry: 1},
      game_object: %GameObjectComponent{},
      movement_block: %MovementBlock{position: {1.0, 1.0, 1.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end

  defp await_entity(guid, attempts \\ 50)
  defp await_entity(_guid, 0), do: flunk("entity did not start")

  defp await_entity(guid, attempts) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> pid
      nil -> Process.sleep(10) && await_entity(guid, attempts - 1)
    end
  end

  defp await_replacement(guid, old_pid, attempts \\ 50)
  defp await_replacement(_guid, _old_pid, 0), do: flunk("entity was not replaced")

  defp await_replacement(guid, old_pid, attempts) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) and pid != old_pid -> pid
      _ -> Process.sleep(10) && await_replacement(guid, old_pid, attempts - 1)
    end
  end

  defp await_absent(guid, attempts \\ 50)
  defp await_absent(_guid, 0), do: flunk("entity did not stop")

  defp await_absent(guid, attempts) do
    case EntityRegistry.whereis(guid) do
      nil -> :ok
      _pid -> Process.sleep(10) && await_absent(guid, attempts - 1)
    end
  end

  defp await_pool_absent(key, attempts \\ 50)
  defp await_pool_absent(_key, 0), do: flunk("spawn pool did not stop")

  defp await_pool_absent(key, attempts) do
    case Registry.lookup(SpawnPool.Registry, key) do
      [] -> :ok
      _present -> Process.sleep(10) && await_pool_absent(key, attempts - 1)
    end
  end
end
