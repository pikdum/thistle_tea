defmodule ThistleTea.Game.World.System.CellActivator do
  @moduledoc """
  Spawns and despawns cells based on nearby players.
  """
  use GenServer

  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.World.SpatialHash

  require Logger

  defstruct cells: MapSet.new()

  @adjacent_cells 2
  @poll_interval 1_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def invalidate do
    GenServer.cast(__MODULE__, :invalidate)
  end

  @impl GenServer
  def init(_) do
    :timer.send_interval(@poll_interval, :poll)
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_cast(:invalidate, state) do
    {:noreply, %{state | cells: MapSet.new()}}
  end

  @impl GenServer
  def handle_info(:poll, %__MODULE__{cells: old_cells} = state) do
    cells = player_cells() |> expand_cells()

    occupied_cells =
      MapSet.union(
        SpatialHash.cells(:mobs),
        SpatialHash.cells(:game_objects)
      )

    to_add = MapSet.difference(cells, old_cells)
    to_remove = MapSet.difference(occupied_cells, cells)

    :ok = start_cells(to_add)
    :ok = stop_cells(to_remove)

    {:noreply, %{state | cells: cells}}
  end

  defp start_cells(cells), do: Enum.each(cells, &start_cell/1)
  defp stop_cells(cells), do: Enum.each(cells, &stop_cell/1)

  defp start_cell(cell) do
    Logger.debug("Activating cell: #{inspect(cell)}")

    Task.start(fn ->
      Loader.Mob.load(cell)
      Loader.GameObject.load(cell)
    end)
  end

  defp stop_cell(cell) do
    Logger.debug("Deactivating cell: #{inspect(cell)}")

    stop_entities(:mobs, cell)
    stop_entities(:game_objects, cell)
  end

  defp stop_entities(table, cell) do
    SpatialHash.entities(table, cell)
    |> Enum.each(&stop_entity/1)
  end

  defp stop_entity({_cell, guid}) do
    World.stop_entity(guid)
  end

  defp player_cells do
    SpatialHash.cells(:players)
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
