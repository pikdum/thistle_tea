defmodule ThistleTea.Game.World.Loader.MapTemplate do
  @moduledoc """
  ETS cache of VMangos map classifications used by gameplay validation.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.Instance.Admission.Policy

  @table_options [:named_table, :public, read_concurrency: true]
  @supported_patch 10
  @dungeon_types [1, 2]
  @battleground_type 3

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.MapTemplate
    |> where([row], row.patch <= @supported_patch)
    |> Mangos.Repo.all()
    |> load()
  end

  def load(rows, table \\ __MODULE__) do
    rows = rows |> Enum.group_by(& &1.entry) |> Enum.map(fn {_entry, versions} -> Enum.max_by(versions, & &1.patch) end)

    Enum.each(rows, fn row ->
      :ets.insert(table, {row.entry, row.map_type, normalize_script_name(row.script_name)})
      :ets.insert(table, {{:player_limit, row.entry}, Map.get(row, :player_limit)})
      :ets.insert(table, {{:reset_delay, row.entry}, Map.get(row, :reset_delay, 0)})
    end)

    dungeons = rows |> Enum.filter(&(&1.map_type in @dungeon_types)) |> Map.new(&{&1.entry, dungeon(&1)})
    :ets.insert(table, {:dungeons, dungeons})
  end

  def dungeons(table \\ __MODULE__) do
    case :ets.lookup(table, :dungeons) do
      [{:dungeons, dungeons}] -> dungeons
      _missing -> %{}
    end
  end

  defp dungeon(row) do
    %Dungeon{
      map_id: row.entry,
      name: Map.get(row, :map_name),
      parent_map: Map.get(row, :parent),
      zone_id: Map.get(row, :linked_zone),
      ghost_entrance: ghost_entrance(row)
    }
  end

  defp ghost_entrance(%{ghost_entrance_map: map, ghost_entrance_x: x, ghost_entrance_y: y})
       when is_integer(map) and map >= 0 and is_number(x) and is_number(y), do: {map, x, y}

  defp ghost_entrance(_row), do: nil

  def dungeon?(map_id), do: dungeon?(__MODULE__, map_id)
  def mount_allowed?(map_id), do: not dungeon?(map_id) or map_id in [209, 269, 309, 509]
  def dungeon?(table, map_id), do: map_type(table, map_id) in @dungeon_types
  def non_raid_dungeon?(map_id), do: non_raid_dungeon?(__MODULE__, map_id)
  def non_raid_dungeon?(table, map_id), do: map_type(table, map_id) == 1
  def battleground?(map_id), do: battleground?(__MODULE__, map_id)
  def battleground?(table, map_id), do: map_type(table, map_id) == @battleground_type
  def instance_script_name(map_id), do: instance_script_name(__MODULE__, map_id)

  def admission_policy(map_id, table \\ __MODULE__) do
    limit =
      case :ets.lookup(table, {:player_limit, map_id}) do
        [{_key, value}] -> value
        _missing -> nil
      end

    %Policy{raid?: map_type(table, map_id) == 2, player_limit: limit}
  end

  def reset_days(map_id, table \\ __MODULE__) do
    case :ets.lookup(table, {:reset_delay, map_id}) do
      [{_key, days}] when is_integer(days) and days > 0 -> days
      _ -> 0
    end
  end

  def instance_script_name(table, map_id) when is_integer(map_id) do
    case :ets.lookup(table, map_id) do
      [{^map_id, _map_type, script_name}] -> script_name
      _missing -> nil
    end
  end

  def instance_script_name(_table, _map_id), do: nil

  defp map_type(table, map_id) when is_integer(map_id) do
    case :ets.lookup(table, map_id) do
      [{^map_id, map_type, _script_name}] -> map_type
      [{^map_id, map_type}] -> map_type
      _missing -> nil
    end
  end

  defp map_type(_table, _map_id), do: nil

  defp normalize_script_name(nil), do: nil
  defp normalize_script_name(""), do: nil
  defp normalize_script_name(script_name), do: script_name
end
