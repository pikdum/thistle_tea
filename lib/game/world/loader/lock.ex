defmodule ThistleTea.Game.World.Loader.Lock do
  @moduledoc """
  Startup lock catalog. Gameplay reads immutable requirements from ETS.
  """
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Lock, as: LockData
  alias ThistleTea.Game.Entity.Data.Lock.Requirement

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table -> table
    end
  end

  def load_all(table \\ __MODULE__), do: load(DBC.all(Lock), table)

  def load(rows, table \\ __MODULE__) do
    Enum.each(rows, fn row ->
      requirements =
        for index <- 0..7,
            type = Map.fetch!(row, :"ty_#{index}"),
            type in [1, 2] do
          %Requirement{
            type: if(type == 1, do: :item, else: :skill),
            index: Map.fetch!(row, :"property_#{index}"),
            skill: Map.fetch!(row, :"required_skill_#{index}") || 0
          }
        end

      :ets.insert(table, {row.id, %LockData{id: row.id, requirements: requirements}})
    end)
  end

  def get(id, table \\ __MODULE__) do
    case :ets.lookup(table, id) do
      [{^id, lock}] -> lock
      _missing -> nil
    end
  end
end
