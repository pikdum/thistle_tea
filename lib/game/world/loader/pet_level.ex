defmodule ThistleTea.Game.World.Loader.PetLevel do
  @moduledoc """
  Startup cache of hunter pet growth and quarter-player experience costs.
  Gameplay progression reads only this translated catalogue.
  """

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.PetLevel

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    xp = Map.new(Mangos.Repo.all(Mangos.PlayerXpForLevel), &{&1.level, div(&1.xp_for_next_level, 4)})

    levels =
      Mangos.Repo.all(from(row in Mangos.PetLevelStats, where: row.entry == 1))
      |> Map.new(fn row ->
        fields = Map.take(row, [:level, :health, :armor, :strength, :agility, :stamina, :intellect, :spirit])
        {row.level, struct!(PetLevel, Map.put(fields, :next_level_xp, Map.get(xp, row.level, 0)))}
      end)

    :ets.insert(table, {:levels, levels})
    :ok
  end

  def levels(table \\ __MODULE__) do
    case :ets.lookup(table, :levels) do
      [{:levels, levels}] -> levels
      _ -> %{}
    end
  end
end
