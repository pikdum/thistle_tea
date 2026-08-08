defmodule ThistleTea.Game.World.Loader.MapTemplate do
  @moduledoc """
  ETS cache of VMangos map classifications used by gameplay validation.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos

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
    rows
    |> Enum.group_by(& &1.entry)
    |> Enum.map(fn {_entry, versions} -> Enum.max_by(versions, & &1.patch) end)
    |> Enum.each(fn row ->
      :ets.insert(table, {row.entry, row.map_type, normalize_script_name(row.script_name)})
    end)
  end

  def dungeon?(map_id), do: dungeon?(__MODULE__, map_id)
  def dungeon?(table, map_id), do: map_type(table, map_id) in @dungeon_types
  def battleground?(map_id), do: battleground?(__MODULE__, map_id)
  def battleground?(table, map_id), do: map_type(table, map_id) == @battleground_type
  def instance_script_name(map_id), do: instance_script_name(__MODULE__, map_id)

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
