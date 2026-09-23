defmodule ThistleTea.Game.OutdoorPvp.ResourceRace do
  @moduledoc "Pure team resource totals and control changes for an outdoor objective."

  defstruct limit: 200, alliance: 0, horde: 0, controller: nil

  def contribute(%__MODULE__{} = race, team) when team in [:alliance, :horde] do
    race = increment(race, team)

    if total(race, team) >= race.limit do
      {%{race | alliance: 0, horde: 0, controller: team}, :captured}
    else
      {race, :contributed}
    end
  end

  def total(%__MODULE__{alliance: total}, :alliance), do: total
  def total(%__MODULE__{horde: total}, :horde), do: total

  defp increment(%__MODULE__{} = race, :alliance), do: %{race | alliance: race.alliance + 1}
  defp increment(%__MODULE__{} = race, :horde), do: %{race | horde: race.horde + 1}
end
