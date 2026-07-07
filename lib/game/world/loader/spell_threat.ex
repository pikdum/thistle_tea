defmodule ThistleTea.Game.World.Loader.SpellThreat do
  @moduledoc """
  Per-spell bonus threat from the vmangos `spell_threat` table: a flat amount
  added when the spell lands and a multiplier scaling its damage threat.
  Lazily cached in ETS, filtered to the 1.12 client build.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.SpellThreat

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, spell_id) do
      [{_id, entry}] -> entry
      _ -> cache(spell_id, load(spell_id))
    end
  rescue
    ArgumentError -> nil
  end

  def get(_spell_id), do: nil

  defp cache(spell_id, entry) do
    :ets.insert(__MODULE__, {spell_id, entry})
    entry
  end

  defp load(spell_id) do
    Mangos.Repo.one(
      from(t in SpellThreat,
        where: t.entry == ^spell_id and t.build_min <= @client_build and t.build_max >= @client_build,
        select: %{threat: t.threat, multiplier: t.multiplier},
        limit: 1
      )
    )
  end
end
