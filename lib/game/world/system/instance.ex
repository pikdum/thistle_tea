defmodule ThistleTea.Game.World.System.Instance do
  @moduledoc """
  Serializes dungeon-copy admission and tears down copies after they become
  empty.
  """
  use GenServer

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.InstanceScript.Effects
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.InstanceEffectSink
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader
  alias ThistleTea.Game.World.Loader.MapTemplate, as: MapTemplateLoader
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  require Logger

  @empty_timeout_ms 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def enter(map_id, guid, server \\ __MODULE__) when is_integer(map_id) and is_integer(guid) do
    GenServer.call(server, {:enter, map_id, guid})
  end

  def leave(guid, world, server \\ __MODULE__)

  def leave(guid, %WorldRef{} = world, server) when is_integer(guid) do
    GenServer.cast(server, {:leave, guid, world})
  end

  def leave(_guid, _world, _server), do: :ok

  def world_for(map_id, guid, server \\ __MODULE__) when is_integer(map_id) and is_integer(guid) do
    GenServer.call(server, {:world_for, map_id, guid})
  end

  def count(server \\ __MODULE__), do: GenServer.call(server, :count)

  def destination(map_id, guid) when is_integer(map_id) and is_integer(guid) do
    if AreaTriggerLoader.instance_map?(map_id) do
      enter(map_id, guid)
    else
      {:ok, WorldRef.open(map_id)}
    end
  end

  def info(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:info, guid})
  end

  def reset(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:reset, guid})
  end

  def switch(guid, %WorldRef{} = world, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:switch, guid, world})
  end

  def command(world, field, value, mode, server \\ __MODULE__) do
    GenServer.call(server, {:command, world, field, value, mode})
  end

  def game_object_used(world, entry, server \\ __MODULE__) do
    GenServer.call(server, {:game_object_used, world, entry})
  end

  def creature_event(world, event, server \\ __MODULE__) do
    GenServer.cast(server, {:creature_event, world, event})
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       instances: %Instance{},
       cleanup_refs: %{},
       script_timer_refs: %{},
       empty_timeout_ms: Keyword.get(opts, :empty_timeout_ms, @empty_timeout_ms),
       cleanup: Keyword.get(opts, :cleanup, &cleanup_world/1),
       owner: Keyword.get(opts, :owner, &owner/1),
       reset_owner: Keyword.get(opts, :reset_owner, &reset_owner/1),
       script_name: Keyword.get(opts, :script_name, &MapTemplateLoader.instance_script_name/1),
       projection: Keyword.get(opts, :projection, InstanceData),
       projection_table: Keyword.get(opts, :projection_table, InstanceData),
       effect_sink: Keyword.get(opts, :effect_sink, &InstanceEffectSink.emit/2)
     }}
  end

  @impl GenServer
  def handle_call({:enter, map_id, guid}, _from, state) do
    owner = state.owner.(guid)
    script_name = state.script_name.(map_id)
    previous = state.instances
    {world, emptied, instances} = Instance.enter(previous, map_id, owner, guid, script_name)

    if is_nil(Instance.copy(previous, world)) do
      state.projection.publish(state.projection_table, Instance.copy(instances, world))
    end

    state =
      %{state | instances: instances}
      |> cancel_cleanup(world)
      |> schedule_cleanup(emptied)

    {:reply, {:ok, world}, state}
  rescue
    error ->
      Logger.warning("Instance admission failed: #{Exception.message(error)}")
      {:reply, {:error, :instance_unavailable}, state}
  end

  def handle_call({:command, world, field, value, mode}, _from, state) do
    case Instance.command(state.instances, world, field, value, mode) do
      {:ok, stored, effects, instances} ->
        state.projection.publish(state.projection_table, Instance.copy(instances, world))
        state = dispatch_effects(%{state | instances: instances}, world, effects)
        {:reply, {:ok, stored}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  rescue
    error ->
      Logger.warning("Instance data command failed: #{Exception.message(error)}")
      {:reply, {:error, :instance_command_failed}, state}
  end

  def handle_call({:game_object_used, world, entry}, _from, state) do
    case Instance.game_object_used(state.instances, world, entry) do
      {:ok, effects, instances} ->
        state.projection.publish(state.projection_table, Instance.copy(instances, world))
        state = dispatch_effects(%{state | instances: instances}, world, effects)
        {:reply, :ok, state}

      {:error, _reason} ->
        {:reply, :ok, state}
    end
  rescue
    error ->
      Logger.warning("Instance game object callback failed: #{Exception.message(error)}")
      {:reply, :ok, state}
  end

  def handle_call({:world_for, map_id, guid}, _from, state) do
    world =
      Instance.world_for_guid(state.instances, map_id, guid) ||
        Instance.world_for(state.instances, map_id, state.owner.(guid))

    {:reply, world, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.instances.copies), state}
  end

  def handle_call({:info, guid}, _from, state) do
    owner = state.owner.(guid)

    copies =
      (Instance.copies_for_guid(state.instances, guid) ++ Instance.copies_for_owner(state.instances, owner))
      |> Enum.uniq_by(& &1.world)
      |> Enum.map(fn copy ->
        %{
          world: copy.world,
          owner: copy.owner,
          members: MapSet.to_list(copy.members),
          script_name: copy.script_name,
          data: copy.data
        }
      end)

    info = %{owner: owner, current: Instance.member_world(state.instances, guid), copies: copies}
    {:reply, info, state}
  end

  def handle_call({:reset, guid}, _from, state) do
    case state.reset_owner.(guid) do
      {:ok, owner} ->
        copies = Instance.copies_for_owner(state.instances, owner)
        {empty, occupied} = Enum.split_with(copies, &(MapSet.size(&1.members) == 0))

        state = Enum.reduce(empty, state, &reset_copy/2)
        result = %{reset: Enum.map(empty, & &1.world), failed: Enum.map(occupied, & &1.world)}
        {:reply, {:ok, result}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:switch, guid, world}, _from, state) do
    case Instance.join_copy(state.instances, guid, world) do
      {:ok, emptied, instances} ->
        state =
          %{state | instances: instances}
          |> cancel_cleanup(world)
          |> schedule_cleanup(emptied)

        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_cast({:leave, guid, world}, state) do
    {instances, emptied} = Instance.leave(state.instances, guid, world)
    {:noreply, schedule_cleanup(%{state | instances: instances}, emptied)}
  end

  def handle_cast({:creature_event, world, event}, state) do
    case Instance.creature_event(state.instances, world, event) do
      {:ok, effects, instances} ->
        state.projection.publish(state.projection_table, Instance.copy(instances, world))
        {:noreply, dispatch_effects(%{state | instances: instances}, world, effects)}

      {:error, _reason} ->
        {:noreply, state}
    end
  rescue
    error ->
      Logger.warning("Instance creature callback failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:cleanup, %WorldRef{} = world, token}, state) do
    case Map.get(state.cleanup_refs, world) do
      {_timer_ref, ^token} -> cleanup_if_empty(state, world)
      _stale -> {:noreply, state}
    end
  end

  def handle_info({:instance_script_timer, %WorldRef{} = world, key, token}, state) do
    case Map.get(state.script_timer_refs, {world, key}) do
      {_timer_ref, ^token} -> run_script_timer(state, world, key)
      _stale -> {:noreply, state}
    end
  end

  defp owner(guid) do
    case PartySystem.group_of(guid) do
      %Party.Group{id: id} -> {:party, id}
      _solo -> {:player, guid}
    end
  end

  defp reset_owner(guid) do
    case PartySystem.group_of(guid) do
      %Party.Group{leader: ^guid, id: id} -> {:ok, {:party, id}}
      %Party.Group{} -> {:error, :not_leader}
      _solo -> {:ok, {:player, guid}}
    end
  end

  defp reset_copy(copy, state) do
    state.cleanup.(copy.world)
    instances = Instance.destroy_empty(state.instances, copy.world)
    state.projection.remove(state.projection_table, copy.world)
    state = state |> cancel_cleanup(copy.world) |> cancel_world_script_timers(copy.world)
    %{state | instances: instances}
  end

  defp schedule_cleanup(state, nil), do: state

  defp schedule_cleanup(state, %WorldRef{} = world) do
    state = cancel_cleanup(state, world)
    token = make_ref()
    timer_ref = Process.send_after(self(), {:cleanup, world, token}, state.empty_timeout_ms)
    %{state | cleanup_refs: Map.put(state.cleanup_refs, world, {timer_ref, token})}
  end

  defp cancel_cleanup(state, %WorldRef{} = world) do
    case Map.pop(state.cleanup_refs, world) do
      {nil, _refs} ->
        state

      {{timer_ref, _token}, refs} ->
        Process.cancel_timer(timer_ref)
        %{state | cleanup_refs: refs}
    end
  end

  defp cleanup_if_empty(state, world) do
    cleanup_refs = Map.delete(state.cleanup_refs, world)

    if Instance.empty?(state.instances, world) do
      state.cleanup.(world)
      instances = Instance.destroy_empty(state.instances, world)
      state.projection.remove(state.projection_table, world)
      state = cancel_world_script_timers(%{state | instances: instances, cleanup_refs: cleanup_refs}, world)
      {:noreply, state}
    else
      {:noreply, %{state | cleanup_refs: cleanup_refs}}
    end
  end

  defp run_script_timer(state, world, key) do
    state = %{state | script_timer_refs: Map.delete(state.script_timer_refs, {world, key})}

    case Instance.timer(state.instances, world, key) do
      {:ok, effects, instances} ->
        state.projection.publish(state.projection_table, Instance.copy(instances, world))
        {:noreply, dispatch_effects(%{state | instances: instances}, world, effects)}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  defp dispatch_effects(state, world, effects) do
    Enum.reduce(effects, state, &dispatch_effect(world, &1, &2))
  end

  defp dispatch_effect(world, %Effects.Schedule{} = effect, state) do
    state = cancel_script_timer(state, world, effect.key)
    token = make_ref()
    timer_ref = Process.send_after(self(), {:instance_script_timer, world, effect.key, token}, effect.delay_ms)
    refs = Map.put(state.script_timer_refs, {world, effect.key}, {timer_ref, token})
    %{state | script_timer_refs: refs}
  end

  defp dispatch_effect(world, %Effects.CancelSchedules{keys: keys}, state) do
    Enum.reduce(keys, state, &cancel_script_timer(&2, world, &1))
  end

  defp dispatch_effect(world, effect, state) do
    state.effect_sink.(world, effect)
    state
  rescue
    error ->
      Logger.warning("Instance effect failed: #{Exception.message(error)}")
      state
  end

  defp cancel_script_timer(state, world, key) do
    case Map.pop(state.script_timer_refs, {world, key}) do
      {nil, _refs} ->
        state

      {{timer_ref, _token}, refs} ->
        Process.cancel_timer(timer_ref)
        %{state | script_timer_refs: refs}
    end
  end

  defp cancel_world_script_timers(state, world) do
    state.script_timer_refs
    |> Map.keys()
    |> Enum.filter(fn {timer_world, _key} -> timer_world == world end)
    |> Enum.reduce(state, fn {_world, key}, state -> cancel_script_timer(state, world, key) end)
  end

  defp cleanup_world(world) do
    SpawnPool.stop_world(world)
    World.stop_world_entities(world)
    CellActivator.deactivate_world(world)
  end
end
