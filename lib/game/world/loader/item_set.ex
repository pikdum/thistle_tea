defmodule ThistleTea.Game.World.Loader.ItemSet do
  @moduledoc """
  Preloads DBC equipment set definitions for database-free gameplay lookups.
  """

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.ItemSet

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table_id -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    for row <- DBC.all(Elixir.ItemSet), do: :ets.insert(table, {row.id, build(row)})
    :ok
  end

  def get(id, table \\ __MODULE__) do
    case :ets.lookup(table, id) do
      [{^id, %ItemSet{} = set}] -> set
      [] -> nil
    end
  end

  defp build(row) do
    bonuses =
      for index <- 0..7,
          spell_id = Map.fetch!(row, :"set_spell_#{index}"),
          pieces = Map.fetch!(row, :"set_threshold_#{index}"),
          spell_id > 0 and pieces > 0,
          do: {pieces, spell_id}

    %ItemSet{
      id: row.id,
      name: row.name_en_gb,
      required_skill: row.required_skill,
      required_skill_rank: row.required_skill_rank,
      bonuses: Enum.sort(bonuses)
    }
  end
end
