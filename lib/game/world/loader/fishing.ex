defmodule ThistleTea.Game.World.Loader.Fishing do
  @moduledoc """
  Cached fishing base-skill levels from the VMangos world seed.
  """
  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.SkillFishingBaseLevel
    |> Mangos.Repo.all()
    |> Enum.each(&:ets.insert(__MODULE__, {&1.entry, &1.skill}))
  end

  def base_skill(area, zone) do
    lookup(area) || lookup(zone) || 0
  end

  defp lookup(id) when is_integer(id) and id > 0 do
    case :ets.lookup(__MODULE__, id) do
      [{^id, skill}] -> skill
      [] -> nil
    end
  end

  defp lookup(_id), do: nil
end
