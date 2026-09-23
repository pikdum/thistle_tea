defmodule ThistleTea.Game.World.Loader.WeatherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Weather.Season
  alias ThistleTea.Game.World.Loader.Weather

  setup [:table]

  describe "load/2" do
    test "caches independent seasons and repairs invalid seed percentages", %{table: table} do
      Weather.load(
        [
          %Mangos.GameWeather{
            zone: 12,
            spring_rain_chance: 20,
            summer_rain_chance: 15,
            fall_snow_chance: 101,
            winter_storm_chance: -1
          }
        ],
        table
      )

      assert Weather.get(12, :spring, table) == %Season{rain: 20, snow: 25, storm: 25}
      assert Weather.get(12, :summer, table).rain == 15
      assert Weather.get(12, :fall, table).snow == 25
      assert Weather.get(12, :winter, table).storm == 25
      assert Weather.get(99, :winter, table) == nil
    end

    @tag :vmangos_db
    test "loads real forest rain, mountain snow, and desert storms", %{table: table} do
      rows = Mangos.Repo.all(Mangos.GameWeather)
      Weather.load(rows, table)
      assert Weather.get(12, :fall, table) == %Season{rain: 20}
      assert Weather.get(1, :winter, table) == %Season{snow: 25}
      assert Weather.get(440, :summer, table) == %Season{storm: 15}
    end
  end

  defp table(_context), do: %{table: :ets.new(:weather_loader_test, [:set, :public])}
end
