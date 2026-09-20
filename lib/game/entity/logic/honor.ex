defmodule ThistleTea.Game.Entity.Logic.Honor do
  @moduledoc """
  Pure honor awards, daily and weekly accounting, and client field projection.
  The caller supplies the game day and completed weekly standing.
  """

  import Bitwise, only: [bor: 2, bsl: 2]

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Honor
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Day
  alias ThistleTea.Game.Entity.Data.Honor.Standing
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Honor.Rank

  @award_types [:honorable, :dishonorable, :bonus, :quest, :other]

  def team(race) when race in [1, 3, 4, 7], do: :alliance
  def team(race) when race in [2, 5, 6, 8], do: :horde
  def team(_race), do: nil

  def creature_award(%Mob{internal: %{creature: creature}} = victim, level) when is_integer(level) do
    cond do
      creature.civilian? and
          (victim.unit.level <= Experience.gray_level(level) or creature.experience_multiplier == 0) ->
        %Award{type: :dishonorable, points: dishonorable_points(level), victim_guid: victim.object.guid}

      creature.racial_leader? ->
        %Award{
          type: :honorable,
          points: 488,
          victim_key: {:creature, victim.object.entry},
          victim_guid: victim.object.guid,
          victim_rank: 19
        }

      true ->
        nil
    end
  end

  def creature_award(%Mob{}, _level), do: nil

  def award(%Honor{} = honor, %Award{type: type, points: points} = award, day)
      when type in @award_types and is_number(points) and points > 0 and is_integer(day) do
    totals = honor.days |> Map.get(day, %Day{}) |> add_award(award)

    honor = %{
      honor
      | days: Map.put(honor.days, day, totals),
        lifetime_honorable_kills: honor.lifetime_honorable_kills + if(type == :honorable, do: 1, else: 0),
        lifetime_dishonorable_kills: honor.lifetime_dishonorable_kills + if(type == :dishonorable, do: 1, else: 0),
        rank_points: if(type == :dishonorable, do: max(honor.rank_points - points, 0.0), else: honor.rank_points)
    }

    refresh_highest_rank(honor)
  end

  def award(%Honor{} = honor, %Award{}, _day), do: honor

  defp add_award(%Day{} = day, %Award{type: :dishonorable}) do
    %{day | dishonorable_kills: day.dishonorable_kills + 1}
  end

  defp add_award(%Day{} = day, %Award{type: :honorable, points: points, victim_key: victim}) do
    victims = if is_nil(victim), do: day.victims, else: Map.update(day.victims, victim, 1, &(&1 + 1))
    %{day | honorable_kills: day.honorable_kills + 1, contribution: day.contribution + points, victims: victims}
  end

  defp add_award(%Day{} = day, %Award{points: points}), do: %{day | contribution: day.contribution + points}

  def victim_kills(%Honor{} = honor, day, victim_key) do
    %Day{victims: victims} = Map.get(honor.days, day, %Day{})
    Map.get(victims, victim_key, 0)
  end

  def totals(%Honor{} = honor, first_day, last_day) do
    Enum.reduce(honor.days, %Day{}, fn
      {day, %Day{} = entry}, totals when day >= first_day and day <= last_day ->
        %{
          totals
          | honorable_kills: totals.honorable_kills + entry.honorable_kills,
            dishonorable_kills: totals.dishonorable_kills + entry.dishonorable_kills,
            contribution: totals.contribution + entry.contribution
        }

      _entry, totals ->
        totals
    end)
  end

  def settle(%Honor{last_settled_week: previous} = honor, week_start, %Standing{})
      when is_integer(previous) and week_start <= previous, do: honor

  def settle(%Honor{} = honor, week_start, %Standing{} = standing) do
    %{
      honor
      | last_week: totals(honor, week_start, week_start + 6),
        last_standing: standing.position,
        last_settled_week: week_start,
        rank_points: standing.rank_points,
        days: Map.filter(honor.days, fn {day, _totals} -> day >= week_start + 6 end)
    }
    |> refresh_highest_rank()
  end

  defp refresh_highest_rank(%Honor{} = honor),
    do: %{honor | highest_rank: max(honor.highest_rank, Rank.number(honor.rank_points))}

  def project(%Honor{} = honor, %Player{} = player, day, week_start) do
    today = Map.get(honor.days, day, %Day{})
    yesterday = Map.get(honor.days, day - 1, %Day{})
    week = totals(honor, week_start, day)

    %{
      player
      | honor_rank: Rank.number(honor.rank_points),
        highest_honor_rank: honor.highest_rank,
        honor_rank_bar: Rank.progress(honor.rank_points),
        session_kills: bor(min(today.honorable_kills, 0xFFFF), bsl(min(today.dishonorable_kills, 0xFFFF), 16)),
        yesterday_kills: yesterday.honorable_kills,
        yesterday_contribution: trunc(yesterday.contribution),
        this_week_kills: week.honorable_kills,
        this_week_contribution: trunc(week.contribution),
        last_week_kills: honor.last_week.honorable_kills,
        last_week_contribution: trunc(honor.last_week.contribution),
        last_week_rank: honor.last_standing,
        lifetime_honorable_kills: honor.lifetime_honorable_kills,
        lifetime_dishonorable_kills: honor.lifetime_dishonorable_kills
    }
  end

  def kill_points(killer_level, victim_level, victim_rank, previous_kills \\ 0)

  def kill_points(killer_level, victim_level, victim_rank, previous_kills)
      when is_integer(killer_level) and killer_level > 0 and is_integer(victim_level) and victim_level > 0 and
             victim_rank in 0..14 and previous_kills in 0..9 do
    level_coefficient(killer_level) * (1 - previous_kills / 10) * 188.3 *
      :math.exp(0.05331 * victim_rank) * level_factor(killer_level, victim_level)
  end

  def kill_points(_killer_level, _victim_level, _victim_rank, _previous_kills), do: 0.0

  defp level_factor(killer, victim) when victim >= killer, do: 1 + min(victim - killer, 4) * 0.05

  defp level_factor(killer, victim) do
    if victim <= Experience.gray_level(killer) do
      0.0
    else
      difference = Experience.zero_difference(killer)
      (difference + victim - killer) / difference
    end
  end

  defp level_coefficient(level) when level >= 60, do: 1.0
  defp level_coefficient(level) when level >= 50, do: 0.9545
  defp level_coefficient(level) when level >= 40, do: 0.5707
  defp level_coefficient(level) when level >= 30, do: 0.3434
  defp level_coefficient(level) when level >= 20, do: 0.2070
  defp level_coefficient(_level), do: 0.1212

  def dishonorable_points(level) when level < 30, do: 10.0
  def dishonorable_points(level) when level <= 35, do: 10 + 1.5 * (level - 29)
  def dishonorable_points(level) when level <= 41, do: 19 + 2 * (level - 35)
  def dishonorable_points(level) when level <= 50, do: 31 + 3.2 * (level - 41)
  def dishonorable_points(level), do: min(60 + 4 * (level - 50), 100.0)
end
