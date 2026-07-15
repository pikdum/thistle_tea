defmodule ThistleTea.Game.World.Loader.Exploration do
  @moduledoc """
  Cached AreaTable exploration metadata and VMangos exploration base XP.
  """
  alias ThistleTea.DB.Mangos.ExplorationBaseXp
  alias ThistleTea.DB.Mangos.Repo

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    load_areas()
    load_base_xp()
  end

  def load_areas do
    AreaTable
    |> ThistleTea.DBC.all()
    |> Enum.each(&:ets.insert(__MODULE__, {{:area, &1.id}, &1}))
  end

  def load_base_xp do
    ExplorationBaseXp
    |> Repo.all()
    |> Enum.each(&:ets.insert(__MODULE__, {{:base_xp, &1.level}, &1.base_xp}))
  end

  def area(area_id) when is_integer(area_id) and area_id > 0 do
    case :ets.lookup(__MODULE__, {:area, area_id}) do
      [{{:area, ^area_id}, area}] -> area
      [] -> nil
    end
  end

  def area(_area_id), do: nil

  def base_xp(level) when is_integer(level) and level > 0 do
    case :ets.lookup(__MODULE__, {:base_xp, level}) do
      [{{:base_xp, ^level}, xp}] -> xp
      [] -> 0
    end
  end

  def base_xp(_level), do: 0
end
