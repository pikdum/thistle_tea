defmodule ThistleTea.Game.World.Loader.SpellScriptName do
  @moduledoc """
  Preloads the latest VMangos spell script labels for the supported client
  build so exceptional spell behavior can dispatch from VMangos data.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellTemplate

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    latest_builds =
      from(s in SpellTemplate,
        where: s.build <= @client_build,
        group_by: s.entry,
        select: %{entry: s.entry, build: max(s.build)}
      )

    SpellTemplate
    |> join(:inner, [s], latest in subquery(latest_builds), on: latest.entry == s.entry and latest.build == s.build)
    |> where([s], s.script_name != "")
    |> select([s], {s.entry, s.script_name})
    |> Mangos.Repo.all()
    |> Enum.each(&:ets.insert(__MODULE__, &1))

    :ok
  end

  def get(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, script_name}] -> script_name
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def get(_spell_id), do: nil
end
