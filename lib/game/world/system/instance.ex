defmodule ThistleTea.Game.World.System.Instance do
  @moduledoc """
  Serializes dungeon-copy admission and tears down copies after they become
  empty.
  """
  use GenServer

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  @empty_timeout_ms 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def enter(map_id, guid, server \\ __MODULE__) when is_integer(map_id) and is_integer(guid) do
    GenServer.call(server, {:enter, map_id, owner(guid), guid})
  end

  def leave(guid, world, server \\ __MODULE__)

  def leave(guid, %WorldRef{} = world, server) when is_integer(guid) do
    GenServer.cast(server, {:leave, guid, world})
  end

  def leave(_guid, _world, _server), do: :ok

  def world_for(map_id, guid, server \\ __MODULE__) when is_integer(map_id) and is_integer(guid) do
    GenServer.call(server, {:world_for, map_id, owner(guid)})
  end

  def count(server \\ __MODULE__), do: GenServer.call(server, :count)

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       instances: %Instance{},
       cleanup_refs: %{},
       empty_timeout_ms: Keyword.get(opts, :empty_timeout_ms, @empty_timeout_ms),
       cleanup: Keyword.get(opts, :cleanup, &cleanup_world/1)
     }}
  end

  @impl GenServer
  def handle_call({:enter, map_id, owner, guid}, _from, state) do
    {world, emptied, instances} = Instance.enter(state.instances, map_id, owner, guid)

    state =
      %{state | instances: instances}
      |> cancel_cleanup(world)
      |> schedule_cleanup(emptied)

    {:reply, {:ok, world}, state}
  end

  def handle_call({:world_for, map_id, owner}, _from, state) do
    {:reply, Instance.world_for(state.instances, map_id, owner), state}
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.instances.copies), state}
  end

  @impl GenServer
  def handle_cast({:leave, guid, world}, state) do
    {instances, emptied} = Instance.leave(state.instances, guid, world)
    {:noreply, schedule_cleanup(%{state | instances: instances}, emptied)}
  end

  @impl GenServer
  def handle_info({:cleanup, %WorldRef{} = world, token}, state) do
    case Map.get(state.cleanup_refs, world) do
      {_timer_ref, ^token} -> cleanup_if_empty(state, world)
      _stale -> {:noreply, state}
    end
  end

  defp owner(guid) do
    case PartySystem.group_of(guid) do
      %Party.Group{id: id} -> {:party, id}
      _solo -> {:player, guid}
    end
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
      {:noreply, %{state | instances: instances, cleanup_refs: cleanup_refs}}
    else
      {:noreply, %{state | cleanup_refs: cleanup_refs}}
    end
  end

  defp cleanup_world(world) do
    SpawnPool.stop_world(world)
    World.stop_world_entities(world)
    CellActivator.deactivate_world(world)
  end
end
