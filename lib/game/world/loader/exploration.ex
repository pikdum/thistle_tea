defmodule ThistleTea.Game.World.Loader.Exploration do
  @moduledoc """
  Cached AreaTable exploration metadata and VMangos exploration base XP. A
  map with a single zone, like most instances, names that zone for places
  the navigation data has no area for.
  """
  alias ThistleTea.DB.DBC
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
    areas = DBC.all(DBC.AreaTable)

    Enum.each(areas, fn area ->
      :ets.insert(__MODULE__, [{{:area, area.id}, area}, {{:area_bit, area.map, area.area_bit}, area.id}])
    end)

    areas
    |> Enum.filter(&(&1.parent_area_table == 0))
    |> Enum.group_by(& &1.map, & &1.id)
    |> Enum.each(fn {map_id, zones} -> :ets.insert(__MODULE__, {{:map_zones, map_id}, zones}) end)
  end

  def sole_zone(map_id) do
    case :ets.lookup(__MODULE__, {:map_zones, map_id}) do
      [{_key, [zone]}] -> zone
      _none_or_many -> nil
    end
  end

  def area_by_bit(map_id, bit) do
    case :ets.lookup(__MODULE__, {:area_bit, map_id, bit}) do
      [{_key, id}] -> area(id)
      [] -> nil
    end
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
