defmodule ThistleTea.Game.Core.GameEvent.FireworksShow do
  @moduledoc """
  vmangos `FireworksShow` and `ToastingGoblets`, the hardcoded game events 6
  and 39.

  During New Year's Eve, the Lunar New Year, the Fourth of July, and Peon Day,
  the fireworks go up over the cities for the first ten minutes of every hour
  from 6 PM to 6 AM. At New Year's and the Lunar New Year, toasting goblets
  follow each show from ten to twenty past the hour. The hours are the realm's
  clock, which the client shows in UTC.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule

  @fireworks 6
  @toasting_goblets 39
  @new_year 34
  @lunar_new_year 38
  @july_4th 41
  @september_30th 42
  @show_holidays [@new_year, @lunar_new_year, @july_4th, @september_30th]
  @toast_holidays [@new_year, @lunar_new_year]
  @changes_at_minutes [0, 10, 21]
  @horizon_hours 25

  @impl Rule
  def events, do: [@fireworks, @toasting_goblets]

  @impl Rule
  def active_events(%DateTime{hour: hour, minute: minute}, scheduled) do
    if night?(hour) do
      show(minute, scheduled) ++ toast(minute, scheduled)
    else
      []
    end
  end

  @impl Rule
  def boundaries(%DateTime{} = now) do
    hour = %{now | minute: 0, second: 0, microsecond: {0, 0}}

    for hours <- 0..@horizon_hours,
        minute <- @changes_at_minutes,
        moment = DateTime.add(%{hour | minute: minute}, hours * 3600),
        DateTime.after?(moment, now),
        do: moment
  end

  defp night?(hour), do: hour <= 6 or hour >= 18

  defp show(minute, scheduled) when minute < 10, do: if(any?(scheduled, @show_holidays), do: [@fireworks], else: [])
  defp show(_minute, _scheduled), do: []

  defp toast(minute, scheduled) when minute in 10..20,
    do: if(any?(scheduled, @toast_holidays), do: [@toasting_goblets], else: [])

  defp toast(_minute, _scheduled), do: []

  defp any?(scheduled, holidays), do: Enum.any?(holidays, &MapSet.member?(scheduled, &1))
end
