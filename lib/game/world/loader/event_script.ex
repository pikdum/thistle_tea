defmodule ThistleTea.Game.World.Loader.EventScript do
  @moduledoc """
  Preloads VMangos `event_scripts` commands by event ID for object-use dispatch.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.EventScript
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    script_ids = Mangos.Repo.all(from(s in EventScript, distinct: true, select: s.id))

    EventScript
    |> Script.load_by_ids(script_ids)
    |> Enum.each(fn {event_id, steps} -> :ets.insert(__MODULE__, {event_id, steps}) end)

    :ok
  end

  def get(event_id) when is_integer(event_id) and event_id > 0 do
    case :ets.lookup(__MODULE__, event_id) do
      [{^event_id, steps}] -> steps
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def get(_event_id), do: []
end
