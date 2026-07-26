defmodule ThistleTea.Game.World.System.CellActivator do
  @moduledoc """
  Spawns cells that are visible to players.
  """
  use GenServer

  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.WorldRef

  require Logger

  @default_max_concurrency 4
  @default_retry_delay_ms 1_000

  defstruct cells: MapSet.new(),
            requested: MapSet.new(),
            queued: MapSet.new(),
            queue: [],
            loading: %{},
            loader: nil,
            max_concurrency: @default_max_concurrency,
            retry_delay_ms: @default_retry_delay_ms

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
    {:ok,
     %__MODULE__{
       loader: Keyword.get(opts, :loader, &load_cell/1),
       max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
       retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)
     }}
  end

  @impl GenServer
  def handle_cast(:invalidate, state) do
    cancel_loading(state.loading)

    {:noreply,
     %{
       state
       | cells: MapSet.new(),
         requested: MapSet.new(),
         queued: MapSet.new(),
         queue: [],
         loading: %{}
     }}
  end

  def handle_cast({:deactivate_world, world}, state) do
    {stopped, loading} =
      Enum.split_with(state.loading, fn {_ref, {_pid, {cell_world, _x, _y}}} -> cell_world == world end)

    cancel_loading(Map.new(stopped))

    state = %{
      state
      | cells: reject_world(state.cells, world),
        requested: reject_world(state.requested, world),
        queued: reject_world(state.queued, world),
        queue: Enum.reject(state.queue, fn {cell_world, _x, _y} -> cell_world == world end),
        loading: Map.new(loading)
    }

    {:noreply, start_available(state)}
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
        state = %{state | cells: MapSet.put(state.cells, cell), loading: loading}
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

  @impl GenServer
  def terminate(_reason, state) do
    cancel_loading(state.loading)
    :ok
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
