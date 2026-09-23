defmodule ThistleTea.Game.World.Loader.Weather do
  @moduledoc "Boot-loaded seasonal weather chances from the read-only world seed."

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Weather.Season

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _id -> table
    end
  end

  def load_all, do: Mangos.GameWeather |> Mangos.Repo.all() |> load()

  def load(rows, table \\ __MODULE__) do
    Enum.each(rows, fn row ->
      seasons = Map.new([:spring, :summer, :fall, :winter], &{&1, season(row, &1)})
      :ets.insert(table, {row.zone, seasons})
    end)
  end

  def get(zone, season, table \\ __MODULE__) do
    case :ets.lookup(table, zone) do
      [{^zone, seasons}] -> Map.get(seasons, season)
      [] -> nil
    end
  end

  defp season(row, season) do
    %Season{
      rain: chance(Map.fetch!(row, :"#{season}_rain_chance")),
      snow: chance(Map.fetch!(row, :"#{season}_snow_chance")),
      storm: chance(Map.fetch!(row, :"#{season}_storm_chance"))
    }
  end

  defp chance(value) when is_integer(value) and value in 0..100, do: value
  defp chance(_value), do: 25
end
