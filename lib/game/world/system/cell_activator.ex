defmodule ThistleTea.Game.World.System.CellActivator do
  @moduledoc """
  Spawns cells that are visible to players.
  """
  use GenServer

  alias ThistleTea.Game.World.Loader

  require Logger

  defstruct cells: MapSet.new(), loader: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def activate(cells, server \\ __MODULE__) do
    GenServer.cast(server, {:activate, cells})
  end

  def invalidate(server \\ __MODULE__) do
    GenServer.cast(server, :invalidate)
  end

  @impl GenServer
  def init(opts) do
    {:ok, %__MODULE__{loader: Keyword.get(opts, :loader, &load_cell/1)}}
  end

  @impl GenServer
  def handle_cast(:invalidate, state) do
    {:noreply, %{state | cells: MapSet.new()}}
  end

  def handle_cast({:activate, cells}, %__MODULE__{cells: old_cells} = state) do
    cells = MapSet.new(cells)
    to_add = MapSet.difference(cells, old_cells)
    :ok = start_cells(to_add, state.loader)
    {:noreply, %{state | cells: MapSet.union(old_cells, cells)}}
  end

  defp start_cells(cells, loader), do: Enum.each(cells, &start_cell(&1, loader))

  defp start_cell(cell, loader) do
    Logger.debug("Activating cell: #{inspect(cell)}")

    Task.start(fn ->
      loader.(cell)
    end)
  end

  defp load_cell(cell) do
    Loader.Mob.load(cell)
    Loader.GameObject.load(cell)
  end
end
