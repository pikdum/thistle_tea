defmodule ThistleTea.Game.World.System.CellActivator do
  @moduledoc """
  Spawns and despawns cells based on nearby players.
  """
  use GenServer

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
    to_add = MapSet.difference(cells, old_cells)
    :ok = start_cells(to_add)
    {:noreply, %{state | cells: cells}}
  end

  defp start_cells(cells), do: Enum.each(cells, &start_cell/1)

  defp start_cell(cell) do
    Logger.debug("Activating cell: #{inspect(cell)}")

    Task.start(fn ->
      Loader.Mob.load(cell)
      Loader.GameObject.load(cell)
    end)
  end

  defp player_cells do
    SpatialHash.cells(:players)
  end

  defp expand_cells(cells) do
    Enum.flat_map(cells, fn {map, x, y} ->
      for dx <- -@adjacent_cells..@adjacent_cells,
          dy <- -@adjacent_cells..@adjacent_cells do
        {map, x + dx, y + dy}
      end
    end)
    |> MapSet.new()
  end
end
