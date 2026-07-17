defmodule ThistleTea.Game.World.Loader.MapTemplate do
  @moduledoc """
  ETS cache of VMangos map classifications used by gameplay validation.
  """
  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true]
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
    |> Mangos.Repo.all()
    |> Enum.each(fn row -> :ets.insert(__MODULE__, {row.entry, row.map_type}) end)
  end

  def dungeon?(map_id), do: dungeon?(__MODULE__, map_id)
  def dungeon?(table, map_id), do: map_type(table, map_id) in @dungeon_types
  def battleground?(map_id), do: battleground?(__MODULE__, map_id)
  def battleground?(table, map_id), do: map_type(table, map_id) == @battleground_type

  defp map_type(table, map_id) when is_integer(map_id) do
    case :ets.lookup(table, map_id) do
      [{^map_id, map_type}] -> map_type
      _missing -> nil
    end
  end

  defp map_type(_table, _map_id), do: nil
end
