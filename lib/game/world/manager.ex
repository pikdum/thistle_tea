defmodule ThistleTea.Game.World.Manager do
  @moduledoc """
  Spawns and despawns cells based on nearby players.
  """
  use GenServer

  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CellRegistry
  alias ThistleTea.Game.World.Mangos.GameObjectSupervisor

  require Logger

  defstruct cells: MapSet.new()

  @adjacent_cells 2
  @poll_interval 1_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    :timer.send_interval(@poll_interval, :poll)
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_info(:poll, %__MODULE__{cells: old_cells} = state) do
    cells = players() |> expand_cells()
    to_add = MapSet.difference(cells, old_cells)
    to_remove = MapSet.difference(old_cells, cells)

    :ok = start_cells(to_add)
    :ok = stop_cells(to_remove)

    {:noreply, %{state | cells: cells}}
  end

  defp start_cells(cells) do
    Enum.each(cells, &start_cell/1)
  end

  defp start_cell(cell) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        World.DynamicSupervisor,
        {GameObjectSupervisor, cell}
      )
  end

  defp stop_cells(cells) do
    Enum.each(cells, &stop_cell/1)
  end

  defp stop_cell(cell) do
    case Registry.lookup(CellRegistry, {GameObjectSupervisor, cell}) do
      [] -> :ok
      [{pid, _}] -> DynamicSupervisor.terminate_child(World.DynamicSupervisor, pid)
    end
  end

  defp players do
    :ets.tab2list(:players) |> MapSet.new(fn {cell, _guid} -> cell end)
  end

  defp expand_cells(cells) do
    Enum.flat_map(cells, fn {map, x, y, z} ->
      for dx <- -@adjacent_cells..@adjacent_cells,
          dy <- -@adjacent_cells..@adjacent_cells,
          dz <- -@adjacent_cells..@adjacent_cells do
        {map, x + dx, y + dy, z + dz}
      end
    end)
    |> MapSet.new()
  end
end
