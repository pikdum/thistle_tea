defmodule ThistleTea.Game.World.Loader.GameObjectScript do
  @moduledoc """
  Preloads VMangos `gameobject_scripts` commands by spawn ID for object-use
  dispatch, and caches the steps of ported C++ object scripts by entry and
  position, with their talk texts resolved.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.GameObjectScript
  alias ThistleTea.Game.Core.AI.GameObjectScript, as: GameObjectScriptCore
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    script_ids = Mangos.Repo.all(from(s in GameObjectScript, distinct: true, select: s.id))

    GameObjectScript
    |> Script.load_by_ids(script_ids)
    |> Enum.each(fn {spawn_id, steps} -> :ets.insert(__MODULE__, {spawn_id, steps}) end)

    :ok
  end

  def get(spawn_id) when is_integer(spawn_id) and spawn_id > 0 do
    case :ets.lookup(__MODULE__, spawn_id) do
      [{^spawn_id, steps}] -> steps
      _ -> []
    end
  rescue
    ArgumentError -> []
  end

  def get(_spawn_id), do: []

  def ported(entry, {_x, _y, _z, _o} = position) when is_integer(entry) do
    if GameObjectScriptCore.ported?(entry) do
      key = {:ported, entry, position}

      case :ets.lookup(__MODULE__, key) do
        [{^key, steps}] ->
          steps

        _ ->
          steps = entry |> GameObjectScriptCore.steps(position) |> Script.resolve_texts()
          :ets.insert(__MODULE__, {key, steps})
          steps
      end
    else
      []
    end
  rescue
    ArgumentError -> []
  end

  def ported(_entry, _position), do: []
end
