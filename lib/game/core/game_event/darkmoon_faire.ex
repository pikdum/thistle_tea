defmodule ThistleTea.Game.Core.GameEvent.DarkmoonFaire do
  @moduledoc """
  vmangos `DarkmoonFaire`, the calendar behind the hardcoded game events 4, 5,
  23, and 24.

  The faire opens on the first Monday of the month and stays a week, in
  Elwynn Forest in even-numbered months and in Mulgore in odd ones. For the
  three days before it opens, carnies put it up on the same site. Like
  vmangos, a month whose first Monday falls on the 1st, 2nd, or 3rd keeps only
  the build days that fall within it.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule

  @elwynn 4
  @mulgore 5
  @elwynn_building 23
  @mulgore_building 24
  @building_days 3
  @open_days 7

  @impl Rule
  def events, do: [@elwynn, @mulgore, @elwynn_building, @mulgore_building]

  @impl Rule
  def active_events(%Date{day: day} = date) do
    opening = first_monday(date)

    cond do
      day + @building_days < opening -> []
      day < opening -> [if(elwynn?(date), do: @elwynn_building, else: @mulgore_building)]
      day < opening + @open_days -> [if(elwynn?(date), do: @elwynn, else: @mulgore)]
      true -> []
    end
  end

  defp elwynn?(%Date{month: month}), do: rem(month, 2) == 0

  defp first_monday(date) do
    first_weekday = date |> Date.beginning_of_month() |> Date.day_of_week()
    rem(8 - first_weekday, 7) + 1
  end
end
