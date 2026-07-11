defmodule ThistleTea.Game.World.SpawnPool do
  @moduledoc """
  Owns one root VMangos pool or singleton spawn and its entity incarnations.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool.Catalog
  alias ThistleTea.Game.World.SpawnPool.Selection
  alias ThistleTea.Game.World.System.GameEvent

  @registry ThistleTea.Game.World.SpawnPool.Registry
  @supervisor ThistleTea.Game.World.SpawnPool.Supervisor

  def start_link(opts) do
    group = Keyword.fetch!(opts, :group)
    GenServer.start_link(__MODULE__, opts, name: via(group))
  end

  def child_spec(opts) do
    group = Keyword.fetch!(opts, :group)
    %{id: {__MODULE__, group}, start: {__MODULE__, :start_link, [opts]}, restart: :permanent}
  end

  def activate(group, cell, blueprint \\ nil) do
    with {:ok, pid} <- ensure_started(group, blueprint) do
      GenServer.cast(pid, {:activate, cell, blueprint})
    end
  end

  def recycle(%{internal: %Internal{spawn: %Spawn{pool_group: group, pool_member: member}}})
      when not is_nil(group) and not is_nil(member) do
    GenServer.cast(via(group), {:recycle, member, self()})
    :pooled
  end

  def recycle(_entity), do: :unpooled

  def deactivate(%{internal: %Internal{spawn: %Spawn{pool_group: group, pool_member: member}}})
      when not is_nil(group) and not is_nil(member) do
    GenServer.cast(via(group), {:deactivate, member, self()})
    :pooled
  end

  def deactivate(_entity), do: :unpooled

  def refresh_all(events) when is_list(events) do
    @registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])
    |> Enum.each(&GenServer.cast(&1, {:refresh, events}))
  end

  def status(group) do
    GenServer.call(via(group), :status)
  end

  defp ensure_started(group, blueprint) do
    case GenServer.whereis(via(group)) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> start_pool(group, blueprint)
    end
  end

  defp start_pool(group, blueprint) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, group: group, blueprint: blueprint}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :already_present} -> wait_for_pool(group)
      other -> other
    end
  end

  defp wait_for_pool(group) do
    case GenServer.whereis(via(group)) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :pool_starting}
    end
  end

  defp via(group), do: {:via, Registry, {@registry, group}}

  @impl GenServer
  def init(opts) do
    group = Keyword.fetch!(opts, :group)
    blueprint = Keyword.get(opts, :blueprint)
    {catalog, blueprints, selection} = initialize(group, blueprint)

    {:ok,
     %{
       group: group,
       catalog: catalog,
       blueprints: blueprints,
       selection: selection,
       active_cells: MapSet.new(),
       running: %{},
       monitors: %{}
     }}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply, %{selected: state.selection.leaves, running: Map.keys(state.running)}, state}
  end

  @impl GenServer
  def handle_cast({:activate, cell, blueprint}, state) do
    state = maybe_put_blueprint(state, blueprint)
    state = %{state | active_cells: MapSet.put(state.active_cells, cell)}
    {:noreply, start_selected(state)}
  end

  def handle_cast({:recycle, member, pid}, state) do
    case Map.get(state.running, member) do
      {^pid, monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])
        :ok = World.stop_entity(pid)

        available = state.blueprints |> Map.keys() |> MapSet.new()
        selection = replace_selection(state, member, available)

        state = %{
          state
          | selection: selection,
            running: Map.delete(state.running, member),
            monitors: Map.delete(state.monitors, monitor_ref)
        }

        {:noreply, start_selected(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:deactivate, member, pid}, state) do
    {:noreply, stop_running_member(state, member, pid)}
  end

  def handle_cast({:refresh, events}, %{group: {:pool, root_id} = group} = state) do
    blueprints = load_blueprints(root_id, events) |> attach_all(group)

    if MapSet.new(Map.keys(blueprints)) == MapSet.new(Map.keys(state.blueprints)) do
      {:noreply, %{state | blueprints: blueprints}}
    else
      state = stop_all(state)
      available = blueprints |> Map.keys() |> MapSet.new()
      selection = Selection.initialize(root_id, state.catalog, available)
      {:noreply, start_selected(%{state | blueprints: blueprints, selection: selection})}
    end
  end

  def handle_cast({:refresh, events}, %{group: {:singleton, _, _}} = state) do
    selected =
      case Map.values(state.blueprints) do
        [blueprint] -> eligible_singleton_selection(state.selection, blueprint, events)
        [] -> %Selection{}
      end

    if selected.leaves == state.selection.leaves do
      {:noreply, state}
    else
      state = stop_all(state)
      {:noreply, start_selected(%{state | selection: selected})}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {member, monitors} ->
        state = %{state | running: Map.delete(state.running, member), monitors: monitors}
        {:noreply, start_selected(state)}
    end
  end

  defp initialize({:singleton, kind, guid}, blueprint) do
    member = {kind, guid}
    catalog = %{pools: %{}, parent: %{}, member_pool: %{member => nil}}
    blueprints = if is_nil(blueprint), do: %{}, else: %{member => attach(blueprint, {:singleton, kind, guid}, member)}
    selection = %Selection{leaves: MapSet.new([member])}
    {catalog, blueprints, selection}
  end

  defp initialize({:pool, root_id} = group, _blueprint) do
    catalog = Catalog.data()
    blueprints = load_blueprints(root_id) |> attach_all(group)
    available = blueprints |> Map.keys() |> MapSet.new()
    {catalog, blueprints, Selection.initialize(root_id, catalog, available)}
  end

  defp load_blueprints(root_id, events \\ GameEvent.get_events()) do
    members = Catalog.root_members(root_id)
    creature_guids = for %{kind: :creature, id: guid} <- members, do: guid
    game_object_guids = for %{kind: :game_object, id: guid} <- members, do: guid
    Map.merge(Loader.Mob.blueprints(creature_guids, events), Loader.GameObject.blueprints(game_object_guids, events))
  end

  defp attach_all(blueprints, group) do
    Map.new(blueprints, fn {member, blueprint} -> {member, attach(blueprint, group, member)} end)
  end

  defp attach(%Mob{internal: internal} = mob, group, member) do
    spawn = %{internal.spawn | pool_group: group, pool_member: member}
    %{mob | internal: %{internal | spawn: spawn}}
  end

  defp attach(%GameObject{internal: internal} = game_object, group, member) do
    spawn = internal.spawn || %Spawn{}
    spawn = %{spawn | pool_group: group, pool_member: member}
    %{game_object | internal: %{internal | spawn: spawn}}
  end

  defp maybe_put_blueprint(state, nil), do: state

  defp maybe_put_blueprint(%{group: group} = state, blueprint) do
    member = member_key(blueprint)
    %{state | blueprints: Map.put(state.blueprints, member, attach(blueprint, group, member))}
  end

  defp replace_selection(%{group: {:pool, root_id}, selection: selection, catalog: catalog}, member, available) do
    Selection.replace(selection, root_id, member, catalog, available)
  end

  defp replace_selection(%{selection: selection}, _member, _available), do: selection

  defp start_selected(state) do
    Enum.reduce(state.selection.leaves, state, fn member, acc ->
      cond do
        Map.has_key?(acc.running, member) -> acc
        not selected_cell_active?(acc, member) -> acc
        true -> start_member(acc, member)
      end
    end)
  end

  defp selected_cell_active?(state, member) do
    case Map.get(state.blueprints, member) do
      nil -> false
      blueprint -> MapSet.member?(state.active_cells, cell(blueprint))
    end
  end

  defp start_member(state, member) do
    blueprint = Map.fetch!(state.blueprints, member)

    case start_blueprint(blueprint) do
      {:ok, pid} -> monitor_member(state, member, pid)
      {:error, {:already_started, pid}} -> monitor_member(state, member, pid)
      :ok -> state
      {:error, _reason} -> state
    end
  end

  defp start_blueprint(%Mob{} = mob), do: Loader.Mob.start_pool_mob(mob)
  defp start_blueprint(%GameObject{} = game_object), do: Loader.GameObject.start_pool_game_object(game_object)

  defp monitor_member(state, member, pid) do
    ref = Process.monitor(pid)

    %{
      state
      | running: Map.put(state.running, member, {pid, ref}),
        monitors: Map.put(state.monitors, ref, member)
    }
  end

  defp member_key(%Mob{internal: %Internal{creature: creature}}), do: {:creature, creature.db_guid}
  defp member_key(%GameObject{object: object}), do: {:game_object, Bitwise.band(object.guid, 0x00FFFFFF)}

  defp cell(%{internal: %Internal{map: map}, movement_block: %{position: {x, y, z, _o}}}) do
    SpatialHash.cell(map, x, y, z)
  end

  defp stop_running_member(state, member, pid) do
    case Map.get(state.running, member) do
      {^pid, monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])
        :ok = World.stop_entity(pid)

        %{
          state
          | running: Map.delete(state.running, member),
            monitors: Map.delete(state.monitors, monitor_ref)
        }

      _ ->
        state
    end
  end

  defp stop_all(state) do
    Enum.reduce(state.running, state, fn {member, {pid, _ref}}, acc ->
      stop_running_member(acc, member, pid)
    end)
  end

  defp eligible_singleton_selection(_selection, %{internal: %Internal{event: nil}} = blueprint, _events) do
    singleton_selection(blueprint)
  end

  defp eligible_singleton_selection(_selection, %{internal: %Internal{event: event}} = blueprint, events) do
    if event in events, do: singleton_selection(blueprint), else: %Selection{}
  end

  defp singleton_selection(blueprint), do: %Selection{leaves: MapSet.new([member_key(blueprint)])}

  @impl GenServer
  def terminate(_reason, state) do
    stop_all(state)
    :ok
  end
end
