defmodule ThistleTea.Game.Entity.Logic.Honor.Rank do
  @moduledoc """
  Vanilla 1.12 honor rank thresholds, faction standings, bracket interpolation,
  weekly decay, and level caps. All inputs are immutable weekly snapshots.
  """

  alias ThistleTea.Game.Entity.Data.Honor.Candidate
  alias ThistleTea.Game.Entity.Data.Honor.Standing

  @brackets [1.0, 0.845, 0.697, 0.566, 0.436, 0.327, 0.228, 0.159, 0.100, 0.060, 0.035, 0.020, 0.008, 0.003]
  @earnings [0, 400, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000, 10_000, 11_000, 12_000, 13_000]
  @minimum_kills 15

  def number(points) when points <= 0, do: 0
  def number(points) when points < 2_000, do: 5
  def number(points), do: min(div(trunc(points), 5_000) + 6, 18)

  def visual(points), do: points |> number() |> visual_from_number()

  def visual_from_number(nil), do: nil
  def visual_from_number(rank) when is_integer(rank), do: max(rank - 4, 0)

  def progress(points) do
    {minimum, maximum} = bounds(number(points))
    points = min(max(points, minimum), maximum)
    trunc((points - minimum) / (maximum - minimum) * 255)
  end

  defp bounds(rank) when rank in [0, 5], do: {0, 2_000}
  defp bounds(6), do: {2_000, 5_000}
  defp bounds(rank), do: {(rank - 6) * 5_000, (rank - 5) * 5_000}

  def decay(points, earning) do
    delta = earning - floor(points * 0.2 + 0.5)
    delta = if delta < 0, do: max(delta / 2, -2_500), else: delta
    max(points + delta, 0.0)
  end

  def maximum(level) when level <= 29, do: 6_500
  def maximum(level) when level <= 35, do: 7_150 + 975 * (level - 30)
  def maximum(level) when level <= 39, do: 12_025 + 1_300 * (level - 35)
  def maximum(level) when level <= 43, do: 17_225 + 1_625 * (level - 39)
  def maximum(level) when level <= 52, do: 23_725 + 2_275 * (level - 43)
  def maximum(level) when level <= 60, do: 44_200 + 2_600 * (level - 52)
  def maximum(_level), do: 65_000

  def weekly(candidates) when is_list(candidates) do
    {eligible, inactive} = Enum.split_with(candidates, &eligible?/1)

    ranked =
      eligible
      |> Enum.group_by(& &1.team)
      |> Enum.flat_map(fn {_team, members} -> rank_faction(members) end)

    inactive =
      Enum.map(inactive, fn %Candidate{} = candidate ->
        {candidate.guid, %Standing{rank_points: decay(candidate.rank_points, 0)}}
      end)

    Map.new(ranked ++ inactive)
  end

  defp eligible?(%Candidate{} = candidate) do
    candidate.team in [:alliance, :horde] and candidate.honorable_kills >= @minimum_kills and candidate.contribution > 0
  end

  defp rank_faction(candidates) do
    candidates = Enum.sort_by(candidates, &{-&1.contribution, &1.guid})
    scores = Enum.map(candidates, & &1.contribution)
    brackets = Enum.map(@brackets, &round(&1 * length(scores)))
    breakpoints = breakpoints(scores, brackets)

    candidates
    |> Enum.with_index(1)
    |> Enum.map(fn {%Candidate{} = candidate, position} ->
      earning = earning(candidate.contribution, brackets, breakpoints)
      points = min(decay(candidate.rank_points, earning), maximum(candidate.level))
      {candidate.guid, %Standing{position: position, earning: earning, rank_points: points}}
    end)
  end

  defp breakpoints(scores, brackets) do
    {points, {_previous, top?}} =
      Enum.map_reduce(1..13, {0, false}, fn index, {previous, top?} ->
        cutoff = Enum.at(brackets, index)
        honor = cutoff_honor(scores, cutoff)

        cond do
          honor > 0 -> {honor / 2, {honor / 2, top?}}
          not top? -> {if(previous > 0, do: hd(scores), else: 0), {0, true}}
          true -> {0, {0, top?}}
        end
      end)

    [0 | points] ++ [if(top?, do: 0, else: hd(scores))]
  end

  defp cutoff_honor(scores, cutoff) when cutoff > 0 do
    case Enum.at(scores, cutoff - 1, 0) do
      honor when honor > 0 -> honor + Enum.at(scores, cutoff, 0)
      _ -> 0
    end
  end

  defp cutoff_honor(_scores, _cutoff), do: 0

  defp earning(contribution, brackets, breakpoints) do
    index =
      Enum.find(0..13, 14, fn index ->
        Enum.at(brackets, index) == 0 or Enum.at(breakpoints, index) > contribution
      end)

    lower = Enum.at(breakpoints, max(index - 1, 0))
    upper = Enum.at(breakpoints, index)
    maximum = Enum.at(@earnings, index)

    if upper > contribution and contribution >= lower do
      minimum = Enum.at(@earnings, max(index - 1, 0))
      minimum + (maximum - minimum) * (contribution - lower) / (upper - lower)
    else
      maximum
    end
  end
end
