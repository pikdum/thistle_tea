defmodule ThistleTea.Game.Weather do
  @moduledoc "Seasonal weather transitions and Vanilla precipitation presentation, independent of clocks and randomness."

  alias ThistleTea.Game.Weather.Season

  defstruct type: :fine, grade: 0.0

  @step 0.33333334
  @heavy 0.6666667

  def season(%Date{} = date) do
    index = rem(div(Date.day_of_year(date) - 1 - 78 + 365, 91), 4)
    Enum.at([:spring, :summer, :fall, :winter], index)
  end

  def set(type, grade) when type in [:fine, :rain, :snow, :storm] and is_number(grade) and grade >= 0 and grade <= 1 do
    {:ok, normalize(%__MODULE__{type: type, grade: grade * 1.0})}
  end

  def set(_type, _grade), do: {:error, :invalid_weather}

  def advance(%__MODULE__{}, nil, _sample), do: %__MODULE__{}
  def advance(%__MODULE__{} = weather, %Season{}, %{change: change}) when change < 30, do: weather

  def advance(%__MODULE__{} = weather, %Season{} = chances, sample) do
    cond do
      sample.change < 60 and weather.grade < @step -> choose(chances, sample)
      sample.change < 60 and weather.type != :fine -> normalize(%{weather | grade: weather.grade - @step})
      sample.change < 90 and weather.type != :fine -> normalize(%{weather | grade: weather.grade + @step})
      weather.type != :fine -> radical_change(weather, chances, sample)
      true -> choose(chances, sample)
    end
  end

  def type_id(%__MODULE__{type: type}), do: type_id(type)
  def type_id(:fine), do: 0
  def type_id(:rain), do: 1
  def type_id(:snow), do: 2
  def type_id(:storm), do: 3

  def sound(%__MODULE__{type: :fine}), do: 0
  def sound(%__MODULE__{grade: grade}) when grade < 0.3, do: 0

  def sound(%__MODULE__{type: type, grade: grade}) do
    base =
      case type do
        :rain -> 8533
        :snow -> 8536
        :storm -> 8556
      end

    cond do
      grade < 0.6 -> base
      grade < 0.9 -> base + 1
      true -> base + 2
    end
  end

  defp radical_change(%__MODULE__{grade: grade} = weather, _chances, _sample) when grade < @step,
    do: %{weather | grade: 0.9999}

  defp radical_change(%__MODULE__{grade: grade} = weather, _chances, %{radical: radical})
       when grade > @heavy and radical < 50, do: normalize(%{weather | grade: grade - @heavy})

  defp radical_change(_weather, chances, sample), do: choose(chances, sample)

  defp choose(%Season{} = chances, sample) do
    type =
      cond do
        sample.kind <= chances.rain -> :rain
        sample.kind <= chances.rain + chances.snow -> :snow
        sample.kind <= chances.rain + chances.snow + chances.storm -> :storm
        true -> :fine
      end

    offset =
      cond do
        sample.change < 90 -> 0.0
        sample.intensity < 50 -> 0.3334
        true -> 0.6667
      end

    normalize(%__MODULE__{type: type, grade: sample.grade * 0.3333 + offset})
  end

  defp normalize(%__MODULE__{type: :fine} = weather), do: %{weather | grade: 0.0}
  defp normalize(%__MODULE__{grade: grade} = weather) when grade >= 1, do: %{weather | grade: 0.9999}
  defp normalize(%__MODULE__{grade: grade} = weather) when grade < 0, do: %{weather | grade: 0.0001}
  defp normalize(%__MODULE__{} = weather), do: weather
end
