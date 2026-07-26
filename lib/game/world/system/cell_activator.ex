defmodule ThistleTea.Game.World.System.CellActivator do
  @moduledoc """
  Spawns cells that are visible to players and reconciles the loaded set
  against player presence: a periodic sweep recomputes wanted cells from
  ground truth, re-asserts missing ones, deactivates cells that stayed
  unwanted past a grace period, and spins whole open worlds down after
  they have been empty for a while.
  """
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.CellIndex
  alias ThistleTea.Game.WorldRef

  require Logger

  @default_max_concurrency 4
  @default_retry_delay_ms 1_000
  @default_sweep_interval_ms 10_000
  @default_grace_ms 90_000
  @default_world_empty_timeout_ms 300_000
  @visibility_cell_radius 3

  defstruct cells: MapSet.new(),
            orphaned: MapSet.new(),
            requested: MapSet.new(),
            queued: MapSet.new(),
            queue: [],
            loading: %{},
            unwanted_since: %{},
            empty_since: %{},
            loader: nil,
            deactivator: nil,
            player_cells: nil,
            pool_worlds: nil,
            world_teardown: nil,
            sweep?: false,
            max_concurrency: @default_max_concurrency,
            retry_delay_ms: @default_retry_delay_ms,
            sweep_interval_ms: @default_sweep_interval_ms,
            grace_ms: @default_grace_ms,
            world_empty_timeout_ms: @default_world_empty_timeout_ms

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def activate(cells, server \\ __MODULE__) do
    GenServer.cast(server, {:activate, cells})
  end

  def invalidate(server \\ __MODULE__) do
    GenServer.cast(server, :invalidate)
  end

  def deactivate_world(%WorldRef{} = world, server \\ __MODULE__) do
    GenServer.cast(server, {:deactivate_world, world})
  end

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      loader: Keyword.get(opts, :loader, &load_cell/1),
      deactivator: Keyword.get(opts, :deactivator, &deactivate_cells/2),
      player_cells: Keyword.get(opts, :player_cells, &occupied_cells/0),
      pool_worlds: Keyword.get(opts, :pool_worlds, &SpawnPool.worlds/0),
      world_teardown: Keyword.get(opts, :world_teardown, &teardown_world_processes/1),
      sweep?: Keyword.get(opts, :sweep, false),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms),
      sweep_interval_ms: Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms),
      grace_ms: Keyword.get(opts, :grace_ms, @default_grace_ms),
      world_empty_timeout_ms: Keyword.get(opts, :world_empty_timeout_ms, @default_world_empty_timeout_ms)
    }

    {:ok, schedule_sweep(state)}
  end

  @impl GenServer
  def handle_cast(:invalidate, state) do
    cancel_loading(state.loading)

    {:noreply,
     %{
       state
       | cells: MapSet.new(),
         orphaned: MapSet.union(state.orphaned, state.cells),
         requested: MapSet.new(),
         queued: MapSet.new(),
         queue: [],
         loading: %{}
     }}
  end

  def handle_cast({:deactivate_world, world}, state) do
    CellIndex.forget_world(world)
    {:noreply, state |> forget_world(world) |> start_available()}
  end

  def handle_cast({:activate, cells}, %__MODULE__{} = state) do
    {:noreply, state |> enqueue(cells) |> start_available()}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    case Map.pop(state.loading, ref) do
      {nil, _loading} ->
        {:noreply, state}

      {{_pid, cell}, loading} when reason == :normal ->
        state = %{
          state
          | cells: MapSet.put(state.cells, cell),
            orphaned: MapSet.delete(state.orphaned, cell),
            loading: loading
        }

        {:noreply, start_available(state)}

      {{_pid, cell}, loading} ->
        Logger.error("Cell activation failed for #{inspect(cell)}: #{inspect(reason)}")
        schedule_retry(state, cell)
        {:noreply, start_available(%{state | loading: loading})}
    end
  end

  def handle_info({:retry_cell, cell}, %__MODULE__{} = state) do
    if MapSet.member?(state.requested, cell) do
      {:noreply, state |> enqueue([cell]) |> start_available()}
    else
      {:noreply, state}
    end
  end

  def handle_info(:sweep, %__MODULE__{} = state) do
    {:noreply, state |> sweep() |> schedule_sweep()}
  end

  @impl GenServer
  def terminate(_reason, state) do
    cancel_loading(state.loading)
    :ok
  end

  defp sweep(%__MODULE__{} = state) do
    now = System.monotonic_time(:millisecond)
    wanted = wanted_cells(state)

    state
    |> reassert(wanted)
    |> track_unwanted(wanted, now)
    |> deactivate_expired(wanted, now)
    |> sweep_empty_worlds(now)
  end

  defp wanted_cells(%__MODULE__{} = state) do
    state.player_cells.()
    |> Enum.filter(&open_world_cell?/1)
    |> Enum.flat_map(&expand_cell/1)
    |> MapSet.new()
  end

  defp occupied_cells do
    :players
    |> SpatialHash.cells()
    |> Enum.flat_map(fn cell -> SpatialHash.entities(:players, cell) end)
    |> Enum.filter(fn {_cell, guid} -> Entity.online?(guid) end)
    |> Enum.flat_map(fn {cell, guid} -> [cell | viewpoint_cells(guid)] end)
  end

  defp viewpoint_cells(guid) do
    with %{viewpoint: viewpoint} when is_integer(viewpoint) and viewpoint > 0 <- Metadata.query(guid, [:viewpoint]),
         {_guid, world, x, y, z} <- SpatialHash.get_entity(viewpoint) do
      [SpatialHash.cell(world, x, y, z)]
    else
      _ -> []
    end
  end

  defp expand_cell({world, cx, cy}) do
    for dx <- -@visibility_cell_radius..@visibility_cell_radius,
        dy <- -@visibility_cell_radius..@visibility_cell_radius do
      {world, cx + dx, cy + dy}
    end
  end

  defp reassert(%__MODULE__{} = state, wanted) do
    missing = MapSet.difference(wanted, known_cells(state))

    if MapSet.size(missing) > 0 do
      state |> enqueue(missing) |> start_available()
    else
      state
    end
  end

  defp track_unwanted(%__MODULE__{} = state, wanted, now) do
    unwanted_since =
      state.cells
      |> MapSet.union(state.orphaned)
      |> MapSet.difference(wanted)
      |> Enum.filter(&open_world_cell?/1)
      |> Map.new(fn cell -> {cell, Map.get(state.unwanted_since, cell, now)} end)

    %{state | unwanted_since: unwanted_since}
  end

  defp deactivate_expired(%__MODULE__{} = state, wanted, now) do
    expired =
      for {cell, since} <- state.unwanted_since, now - since >= state.grace_ms, into: MapSet.new() do
        cell
      end

    if MapSet.size(expired) > 0 do
      confirmed = state.deactivator.(expired, wanted)
      Logger.debug("Deactivated #{MapSet.size(confirmed)} cells")
      CellIndex.forget_cells(confirmed)

      %{
        state
        | cells: MapSet.difference(state.cells, confirmed),
          orphaned: MapSet.difference(state.orphaned, confirmed),
          requested: MapSet.difference(state.requested, confirmed),
          unwanted_since: Map.drop(state.unwanted_since, MapSet.to_list(confirmed))
      }
    else
      state
    end
  end

  defp deactivate_cells(cells, wanted) do
    cells
    |> CellIndex.pools_for()
    |> Enum.reduce(MapSet.new(cells), fn {pool_key, pool_cells}, confirmed ->
      try do
        :ok = SpawnPool.deactivate_cells(pool_key, pool_cells, wanted)
        confirmed
      catch
        :exit, reason ->
          Logger.warning("Cell deactivation skipped for pool #{inspect(pool_key)}: #{inspect(reason)}")
          MapSet.difference(confirmed, MapSet.new(pool_cells))
      end
    end)
  end

  defp sweep_empty_worlds(%__MODULE__{} = state, now) do
    empty_since =
      state
      |> loaded_open_worlds()
      |> MapSet.difference(populated_worlds(state))
      |> Map.new(fn world -> {world, Map.get(state.empty_since, world, now)} end)

    empty_since
    |> Enum.filter(fn {_world, since} -> now - since >= state.world_empty_timeout_ms end)
    |> Enum.reduce(%{state | empty_since: empty_since}, fn {world, _since}, acc ->
      teardown_world(acc, world)
    end)
  end

  defp teardown_world(%__MODULE__{} = state, world) do
    if MapSet.member?(populated_worlds(state), world) do
      state
    else
      Logger.info("Spinning down empty world: #{inspect(world)}")
      state.world_teardown.(world)
      state |> forget_world(world) |> start_available()
    end
  end

  defp teardown_world_processes(world) do
    SpawnPool.stop_world(world)
    World.stop_world_entities(world, except: [:corpse])
    CellIndex.forget_world(world)
  end

  defp loaded_open_worlds(%__MODULE__{} = state) do
    ledger_worlds =
      state.cells
      |> MapSet.union(state.orphaned)
      |> Enum.filter(&open_world_cell?/1)
      |> MapSet.new(fn {world, _x, _y} -> world end)

    pool_worlds =
      state.pool_worlds.()
      |> Enum.filter(&open_world?/1)
      |> MapSet.new()

    MapSet.union(ledger_worlds, pool_worlds)
  end

  defp populated_worlds(%__MODULE__{} = state) do
    state.player_cells.()
    |> MapSet.new(fn {world, _x, _y} -> world end)
  end

  defp open_world_cell?({world, _x, _y}), do: open_world?(world)

  defp open_world?(%WorldRef{instance_id: instance_id}), do: is_nil(instance_id)
  defp open_world?(_world), do: true

  defp forget_world(%__MODULE__{} = state, world) do
    {stopped, loading} =
      Enum.split_with(state.loading, fn {_ref, {_pid, {cell_world, _x, _y}}} -> cell_world == world end)

    cancel_loading(Map.new(stopped))

    %{
      state
      | cells: reject_world(state.cells, world),
        orphaned: reject_world(state.orphaned, world),
        requested: reject_world(state.requested, world),
        queued: reject_world(state.queued, world),
        queue: Enum.reject(state.queue, fn {cell_world, _x, _y} -> cell_world == world end),
        loading: Map.new(loading),
        unwanted_since: Map.reject(state.unwanted_since, fn {{cell_world, _x, _y}, _since} -> cell_world == world end),
        empty_since: Map.delete(state.empty_since, world)
    }
  end

  defp enqueue(%__MODULE__{} = state, cells) do
    cells = prioritize(cells)
    requested = MapSet.union(state.requested, MapSet.new(cells))
    known = known_cells(state)
    new_cells = Enum.reject(cells, &MapSet.member?(known, &1))

    %{
      state
      | requested: requested,
        queued: MapSet.union(state.queued, MapSet.new(new_cells)),
        queue: new_cells ++ state.queue
    }
  end

  defp start_available(%__MODULE__{} = state) when map_size(state.loading) >= state.max_concurrency, do: state

  defp start_available(%__MODULE__{queue: []} = state), do: state

  defp start_available(%__MODULE__{queue: [cell | rest]} = state) do
    Logger.debug("Activating cell: #{inspect(cell)}")
    {pid, ref} = spawn_monitor(fn -> state.loader.(cell) end)

    state = %{
      state
      | queue: rest,
        queued: MapSet.delete(state.queued, cell),
        loading: Map.put(state.loading, ref, {pid, cell})
    }

    start_available(state)
  end

  defp known_cells(%__MODULE__{} = state) do
    loading =
      state.loading
      |> Map.values()
      |> MapSet.new(fn {_pid, cell} -> cell end)

    state.cells
    |> MapSet.union(state.queued)
    |> MapSet.union(loading)
  end

  defp prioritize(cells) do
    cells = Enum.to_list(cells)

    case cells do
      [] ->
        []

      _ ->
        count = length(cells)
        center_x = Enum.sum(Enum.map(cells, &elem(&1, 1))) / count
        center_y = Enum.sum(Enum.map(cells, &elem(&1, 2))) / count
        Enum.sort_by(cells, fn {_world, x, y} -> abs(x - center_x) + abs(y - center_y) end)
    end
  end

  defp schedule_retry(%__MODULE__{retry_delay_ms: retry_delay_ms}, cell) do
    Process.send_after(self(), {:retry_cell, cell}, retry_delay_ms)
  end

  defp schedule_sweep(%__MODULE__{sweep?: true} = state) do
    Process.send_after(self(), :sweep, state.sweep_interval_ms)
    state
  end

  defp schedule_sweep(%__MODULE__{} = state), do: state

  defp cancel_loading(loading) do
    Enum.each(loading, fn {ref, {pid, _cell}} ->
      Process.demonitor(ref, [:flush])
      Process.exit(pid, :kill)
    end)
  end

  defp reject_world(cells, world) do
    cells
    |> Enum.reject(fn {cell_world, _x, _y} -> cell_world == world end)
    |> MapSet.new()
  end

  defp load_cell(cell) do
    Loader.Mob.load(cell)
    Loader.GameObject.load(cell)
  end
end
