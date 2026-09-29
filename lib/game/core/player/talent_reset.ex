defmodule ThistleTea.Game.Core.Player.TalentReset do
  @moduledoc """
  Retained talent reset history, independent of the current talent allocation,
  with vanilla reset prices and monthly decay. Quotes are pure; only a
  successful purchase advances the price history.
  """
  alias ThistleTea.Game.Core.Player.TalentReset

  defstruct [:last_reset_at, multiplier: 0]

  @month_ms 30 * 24 * 60 * 60 * 1_000

  def cost(%TalentReset{} = history, now) do
    case multiplier(history, now) do
      0 -> 10_000
      value -> value * 50_000
    end
  end

  def purchase(%TalentReset{} = history, money, now) do
    cost = cost(history, now)

    if money >= cost do
      updated = %{history | multiplier: min(multiplier(history, now) + 1, 10), last_reset_at: now}
      {:ok, updated, money - cost}
    else
      {:error, :not_enough_money}
    end
  end

  defp multiplier(%TalentReset{last_reset_at: nil, multiplier: value}, _now), do: min(value, 10)

  defp multiplier(%TalentReset{last_reset_at: last, multiplier: value}, now) do
    months = div(max(now - last, 0), @month_ms)
    floor = if value >= 2, do: 2, else: 0
    value |> min(10) |> Kernel.-(months) |> max(floor)
  end
end
