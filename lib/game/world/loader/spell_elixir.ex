defmodule ThistleTea.Game.World.Loader.SpellElixir do
  @moduledoc """
  Preloads consumable exclusivity masks for the supported vanilla build.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @client_build 5875
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.SpellElixir
    |> where([row], row.build_min <= @client_build and row.build_max >= @client_build)
    |> select([row], {row.entry, row.mask})
    |> Mangos.Repo.all()
    |> then(&:ets.insert(__MODULE__, &1))

    :ok
  end

  def get(spell_id) do
    case :ets.lookup(__MODULE__, spell_id) do
      [{^spell_id, mask}] -> mask
      _missing -> 0
    end
  rescue
    ArgumentError -> 0
  end
end
