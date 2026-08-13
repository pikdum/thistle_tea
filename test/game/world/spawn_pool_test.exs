defmodule ThistleTea.Game.World.SpawnPoolTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.Supervisor, as: SpawnPoolSupervisor
  alias ThistleTea.Game.WorldRef

  describe "singleton lifecycle" do
    test "recycles a persistent entity into a fresh process" do
      low_guid = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, 1, low_guid)
      group = {:singleton, :game_object, low_guid}
      key = {WorldRef.open(0), group}
      blueprint = game_object(guid)

      :ok = SpawnPool.activate(group, {WorldRef.open(0), 0, 0}, blueprint)
      first_pid = EntityRegistry.whereis(guid)
      assert is_pid(first_pid)

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
      SpawnPoolSupervisor.terminate_child(pool_pid)
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
      SpawnPoolSupervisor.terminate_child(pool_pid)
    end

    test "suspends a scripted object until its cell is activated again" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      pid = await_entity(guid)

      send(pid, {:script_remove_object, nil})
      await_absent(guid)

      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == nil

      :ok = SpawnPool.activate(group, cell)
      await_replacement(guid, pid)

      stop_pool(key)
    end

    test "reactivates a scripted object after its respawn delay" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      pid = await_entity(guid)

      send(pid, {:script_remove_object, 100})
      await_absent(guid)
      await_replacement(guid, pid)

      stop_pool(key)
    end

    test "activates a live game object through its owner" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      pid = await_entity(guid)

      send(pid, {:script_activate_object, Guid.from_low_guid(:player, 1)})
      await_game_object_state(pid, 1)

      stop_pool(key)
    end

    test "executes immediate and delayed scripts through the game object owner" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      await_entity(guid)

      steps = [
        %ScriptStep{command: :set_game_object_state, datalong: 1},
        %ScriptStep{command: :set_game_object_state, datalong: 2, delay_ms: 200}
      ]

      Entity.start_script(guid, steps, Guid.from_low_guid(:player, 1))
      pid = await_game_object_state_by_guid(guid, 1)
      await_game_object_state(pid, 2)

      stop_pool(key)
    end

    test "operates and restores a scripted door through its spawn pool" do
      {guid, group, world, key, cell} = singleton_fixture()
      blueprint = put_in(game_object(guid).game_object.state, 1)

      :ok = SpawnPool.activate(group, cell, blueprint)
      pid = await_entity(guid)

      :ok = SpawnPool.operate_game_object(world, blueprint, :open, 300)
      await_game_object_state(pid, 0)
      await_game_object_state(pid, 1)

      stop_pool(key)
    end

    test "temporarily respawns a suspended game object" do
      {guid, group, world, key, cell} = singleton_fixture()
      blueprint = game_object(guid)

      :ok = SpawnPool.activate(group, cell, blueprint)
      pid = await_entity(guid)
      send(pid, {:script_remove_object, nil})
      await_absent(guid)
      await_pool_running(key, [])

      :ok = SpawnPool.respawn_game_object(world, blueprint, 500)
      replacement = await_replacement(guid, pid)
      refute replacement == pid
      await_absent(guid, 100)

      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == nil

      stop_pool(key)
    end

    test "loads and despawns a game object spawn with delayed reactivation" do
      {guid, _group, world, key, _cell} = singleton_fixture()
      blueprint = game_object(guid)

      :ok = SpawnPool.load_game_object(world, blueprint)
      pid = await_entity(guid)

      :ok = SpawnPool.suspend_game_object(world, blueprint, 100)
      await_absent(guid)
      await_replacement(guid, pid)

      stop_pool(key)
    end

    test "suspends a game object by its database guid" do
      {guid, _group, world, key, _cell} = singleton_fixture()
      blueprint = game_object(guid)

      :ok = SpawnPool.load_game_object(world, blueprint)
      await_entity(guid)

      :ok = SpawnPool.suspend_game_object(world, Guid.low_guid(guid))
      await_absent(guid)

      stop_pool(key)
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

      SpawnPoolSupervisor.terminate_child(second_pid)
    end
  end

  describe "deactivate_cells/3" do
    test "stops members whose home cell went inactive and reactivates from cached blueprints" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      await_entity(guid)

      :ok = SpawnPool.deactivate_cells(key, [cell], MapSet.new())
      await_absent(guid)

      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == nil

      :ok = SpawnPool.activate(group, cell)
      await_entity(guid)

      stop_pool(key)
    end

    test "defers busy members until a drain tick clears them" do
      {guid, group, _world, key, cell} = singleton_fixture()

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      pid = await_entity(guid)

      Metadata.update(guid, %{in_combat: true})
      :ok = SpawnPool.deactivate_cells(key, [cell], MapSet.new())

      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == pid

      Metadata.update(guid, %{in_combat: false})
      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, key)
      send(pool_pid, :drain_tick)
      await_absent(guid)

      stop_pool(key)
    end

    test "defers members observed by players until they leave" do
      {guid, group, world, key, cell} = singleton_fixture()
      player_guid = System.unique_integer([:positive])
      SpatialHash.update(:players, player_guid, world, 1.0, 1.0, 1.0)
      on_exit(fn -> SpatialHash.remove(:players, player_guid) end)

      :ok = SpawnPool.activate(group, cell, game_object(guid))
      pid = await_entity(guid)

      :ok = SpawnPool.deactivate_cells(key, [cell], MapSet.new([cell]))
      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == pid

      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, key)
      send(pool_pid, :drain_tick)
      Process.sleep(50)
      assert EntityRegistry.whereis(guid) == pid

      SpatialHash.remove(:players, player_guid)
      send(pool_pid, :drain_tick)
      await_absent(guid)

      stop_pool(key)
    end
  end

  defp singleton_fixture do
    low_guid = 8_000_000 + System.unique_integer([:positive])
    guid = Guid.from_low_guid(:game_object, 1, low_guid)
    group = {:singleton, :game_object, low_guid}
    world = WorldRef.open(0)
    cell = SpatialHash.cell(world, 1.0, 1.0, 1.0)
    {guid, group, world, {world, group}, cell}
  end

  defp stop_pool(key) do
    [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, key)
    SpawnPoolSupervisor.terminate_child(pool_pid)
  end

  defp game_object(guid) do
    %GameObject{
      object: %Object{guid: guid, entry: 1},
      game_object: %GameObjectComponent{state: 0},
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

  defp await_game_object_state(pid, expected_state, attempts \\ 50)
  defp await_game_object_state(_pid, _expected_state, 0), do: flunk("game object state did not change")

  defp await_game_object_state(pid, expected_state, attempts) do
    case :sys.get_state(pid) do
      %GameObject{game_object: %GameObjectComponent{state: ^expected_state}} ->
        :ok

      %GameObject{} ->
        Process.sleep(10)
        await_game_object_state(pid, expected_state, attempts - 1)
    end
  end

  defp await_game_object_state_by_guid(guid, expected_state, attempts \\ 50)
  defp await_game_object_state_by_guid(_guid, _expected_state, 0), do: flunk("game object state did not change")

  defp await_game_object_state_by_guid(guid, expected_state, attempts) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) ->
        case :sys.get_state(pid) do
          %GameObject{game_object: %GameObjectComponent{state: ^expected_state}} ->
            pid

          %GameObject{} ->
            Process.sleep(10)
            await_game_object_state_by_guid(guid, expected_state, attempts - 1)
        end

      nil ->
        Process.sleep(10)
        await_game_object_state_by_guid(guid, expected_state, attempts - 1)
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

  defp await_pool_running(key, expected, attempts \\ 50)
  defp await_pool_running(_key, _expected, 0), do: flunk("spawn pool running members did not change")

  defp await_pool_running(key, expected, attempts) do
    case SpawnPool.status(key) do
      %{running: ^expected} -> :ok
      _status -> Process.sleep(10) && await_pool_running(key, expected, attempts - 1)
    end
  end
end
