defmodule ThistleTea.Game.WeatherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgWeather
  alias ThistleTea.Game.Weather
  alias ThistleTea.Game.Weather.Season

  describe "season/1" do
    test "uses the Vanilla day-of-year season boundaries" do
      assert Weather.season(~D[2026-01-01]) == :winter
      assert Weather.season(~D[2026-03-18]) == :winter
      assert Weather.season(~D[2026-03-19]) == :spring
      assert Weather.season(~D[2026-06-17]) == :spring
      assert Weather.season(~D[2026-06-18]) == :summer
      assert Weather.season(~D[2026-09-16]) == :summer
      assert Weather.season(~D[2026-09-17]) == :fall
      assert Weather.season(~D[2026-12-16]) == :fall
      assert Weather.season(~D[2026-12-17]) == :winter
    end
  end

  describe "advance/3" do
    test "keeps unchanged rolls and handles gradual improvement and worsening" do
      rain = %Weather{type: :rain, grade: 0.7}
      chances = %Season{rain: 100}
      assert Weather.advance(rain, chances, sample(change: 29)) == rain
      assert_in_delta Weather.advance(rain, chances, sample(change: 30)).grade, 0.36666666, 0.000001
      assert Weather.advance(rain, chances, sample(change: 60)).grade == 0.9999
      assert Weather.advance(rain, nil, sample()) == %Weather{}
    end

    test "selects precipitation from cumulative seasonal chances" do
      chances = %Season{rain: 20, snow: 30, storm: 10}

      for {roll, expected} <- [
            {1, :rain},
            {20, :rain},
            {21, :snow},
            {50, :snow},
            {51, :storm},
            {60, :storm},
            {61, :fine},
            {100, :fine}
          ] do
        weather = Weather.advance(%Weather{}, chances, sample(kind: roll))
        assert weather.type == expected
        assert weather.grade == if(expected == :fine, do: 0.0, else: 0.3333)
      end

      assert Weather.advance(%Weather{type: :rain, grade: 0.1}, %Season{}, sample(change: 30)) == %Weather{}
    end

    test "radical changes escalate light weather or replace and soften heavy weather" do
      chances = %Season{snow: 100}

      assert Weather.advance(%Weather{type: :rain, grade: 0.2}, chances, sample(change: 90)) ==
               %Weather{type: :rain, grade: 0.9999}

      softened = Weather.advance(%Weather{type: :storm, grade: 0.9}, chances, sample(change: 90, radical: 49))
      assert softened.type == :storm
      assert_in_delta softened.grade, 0.2333333, 0.000001

      changed =
        Weather.advance(%Weather{type: :rain, grade: 0.9}, chances, sample(change: 90, radical: 50, intensity: 50))

      assert changed == %Weather{type: :snow, grade: 0.9999}
      medium = Weather.advance(%Weather{}, chances, sample(change: 90, intensity: 49, grade: 0.0))
      assert medium == %Weather{type: :snow, grade: 0.3334}
    end
  end

  describe "set/2" do
    test "normalizes client-safe intensities and rejects invalid inputs" do
      assert Weather.set(:rain, 1) == {:ok, %Weather{type: :rain, grade: 0.9999}}
      assert Weather.set(:fine, 0.8) == {:ok, %Weather{}}

      for {type, grade} <- [{:rain, -0.1}, {:snow, 1.1}, {:lava, 0.2}, {:fine, nil}] do
        assert Weather.set(type, grade) == {:error, :invalid_weather}
      end
    end
  end

  describe "sound/1" do
    test "encodes Vanilla types and all sound thresholds in the thirteen-byte packet" do
      for {type, type_id, base} <- [{:rain, 1, 8533}, {:snow, 2, 8536}, {:storm, 3, 8556}],
          {grade, offset} <- [{0.2999, nil}, {0.3, 0}, {0.5999, 0}, {0.6, 1}, {0.8999, 1}, {0.9, 2}] do
        weather = %Weather{type: type, grade: grade}
        expected_sound = if offset, do: base + offset, else: 0
        assert Weather.sound(weather) == expected_sound

        packet = %SmsgWeather{weather_type: Weather.type_id(weather), grade: grade, sound_id: Weather.sound(weather)}

        assert <<^type_id::little-32, encoded::little-float-32, ^expected_sound::little-32, 0>> =
                 SmsgWeather.to_binary(packet)

        assert_in_delta encoded, grade, 0.000001
      end

      assert SmsgWeather.to_binary(%SmsgWeather{}) == <<0::104>>
      assert Weather.sound(%Weather{}) == 0
    end
  end

  defp sample(overrides \\ []) do
    Map.merge(%{change: 60, kind: 1, radical: 0, intensity: 0, grade: 1.0}, Map.new(overrides))
  end
end
