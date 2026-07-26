defmodule ThistleTea.Game.World.SpawnPool.CellIndex do
  @moduledoc """
  ETS index from activated cell to the spawn pool keys holding it, so cell
  deactivation reaches only the pools that matter instead of scanning the
  registry.
  """
  @table_options [:named_table, :public, :bag, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _tid -> table
    end
  end

  def register(cell, pool_key, table \\ __MODULE__) do
    init(table)
    :ets.insert(table, {cell, pool_key})
    :ok
  end

  def pools_for(cells, table \\ __MODULE__) do
    init(table)

    cells
    |> Enum.flat_map(fn cell -> :ets.lookup(table, cell) end)
    |> Enum.group_by(fn {_cell, pool_key} -> pool_key end, fn {cell, _pool_key} -> cell end)
  end

  def forget_cells(cells, table \\ __MODULE__) do
    init(table)
    Enum.each(cells, fn cell -> :ets.delete(table, cell) end)
    :ok
  end

  def forget_world(world, table \\ __MODULE__) do
    init(table)
    :ets.match_delete(table, {{world, :_, :_}, :_})
    :ok
  end
end
