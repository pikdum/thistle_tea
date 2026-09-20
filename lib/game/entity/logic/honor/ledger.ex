defmodule ThistleTea.Game.Entity.Logic.Honor.Ledger do
  @moduledoc """
  Pure realm-wide honor accounting. Weekly standings are settled for every
  registered character together, including offline characters, before new
  awards are recorded. A runtime coordinator supplies days and owns writes.
  """

  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Candidate
  alias ThistleTea.Game.Entity.Data.Honor.Entry
  alias ThistleTea.Game.Entity.Logic.Honor
  alias ThistleTea.Game.Entity.Logic.Honor.Rank

  defstruct [:day, :week_start, entries: %{}]

  def new(day, weekday \\ 2) when is_integer(day) and weekday in 1..7 do
    %__MODULE__{day: day, week_start: day - Integer.mod(day + 4 - weekday, 7)}
  end

  def register(%__MODULE__{} = ledger, guid, team, level)
      when is_integer(guid) and guid > 0 and team in [:alliance, :horde] and is_integer(level) and level > 0 do
    entry =
      case Map.get(ledger.entries, guid) do
        %Entry{} = entry -> %{entry | team: team, level: level}
        nil -> %Entry{guid: guid, team: team, level: level}
      end

    put_entry(ledger, entry)
  end

  def advance(%__MODULE__{day: previous} = ledger, day) when day <= previous, do: ledger

  def advance(%__MODULE__{week_start: week_start} = ledger, day) when day >= week_start + 7 do
    candidates = Enum.map(ledger.entries, fn {_guid, entry} -> weekly_candidate(entry, week_start) end)
    standings = Rank.weekly(candidates)

    entries =
      Map.new(ledger.entries, fn {guid, %Entry{} = entry} ->
        {guid, %{entry | honor: Honor.settle(entry.honor, week_start, Map.fetch!(standings, guid))}}
      end)

    %{ledger | week_start: week_start + 7, entries: entries}
    |> advance(day)
  end

  def advance(%__MODULE__{} = ledger, day), do: %{ledger | day: day}

  defp weekly_candidate(%Entry{} = entry, week_start) do
    totals = Honor.totals(entry.honor, week_start, week_start + 6)

    %Candidate{
      guid: entry.guid,
      team: entry.team,
      level: entry.level,
      honorable_kills: totals.honorable_kills,
      contribution: totals.contribution,
      rank_points: entry.honor.rank_points
    }
  end

  def award(%__MODULE__{} = ledger, guid, %Award{} = award) do
    case Map.get(ledger.entries, guid) do
      %Entry{} = entry -> put_entry(ledger, %{entry | honor: Honor.award(entry.honor, award, ledger.day)})
      nil -> ledger
    end
  end

  def player_kill(%__MODULE__{} = ledger, killer_guid, victim_guid, share) when is_number(share) and share > 0 do
    case {Map.get(ledger.entries, killer_guid), Map.get(ledger.entries, victim_guid)} do
      {%Entry{} = killer, %Entry{} = victim} when killer.team != victim.team ->
        kill_award(ledger, killer, victim, share)

      _ineligible ->
        {ledger, nil}
    end
  end

  def player_kill(%__MODULE__{} = ledger, _killer_guid, _victim_guid, _share), do: {ledger, nil}

  defp kill_award(ledger, killer, victim, share) do
    victim_key = {:player, victim.guid}
    count = Honor.victim_kills(killer.honor, ledger.day, victim_key)
    rank = Rank.visual(victim.honor.rank_points)
    points = trunc(Honor.kill_points(killer.level, victim.level, rank, count) * share)

    if points > 0 do
      award = %Award{
        type: :honorable,
        points: points,
        victim_key: victim_key,
        victim_guid: victim.guid,
        victim_rank: max(Rank.number(victim.honor.rank_points), 5)
      }

      {award(ledger, killer.guid, award), award}
    else
      {ledger, nil}
    end
  end

  defp put_entry(%__MODULE__{} = ledger, %Entry{guid: guid} = entry) do
    %{ledger | entries: Map.put(ledger.entries, guid, entry)}
  end
end
