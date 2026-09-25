defmodule ThistleTea.Game.Battleground.AlteracValley.Rewards do
  @moduledoc "Alterac objective honor, faction reputation, and surviving-objective match rewards."

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Roster

  @bonuses %{
    general: {6, 350, 525},
    captain: {3, 125, 185},
    commander: {1, 12, 18},
    tower: {2, 12, 18},
    surviving_tower: {3, 12, 18},
    surviving_captain: {3, 125, 175},
    graveyard: {1, 12, 18},
    mine: {1, 24, 36}
  }
  @duration_scaled [:general, :surviving_tower, :graveyard, :mine]

  def objective(%AlteracValley{} = match, team, kind, now, count \\ 1) do
    {kills, normal_rep, weekend_rep} = Map.fetch!(@bonuses, kind)
    multiplier = if kind in @duration_scaled, do: duration_modifier(match, now), else: 1.0
    honor = trunc(198 * kills * count * multiplier)
    reputation = count * if(match.weekend?, do: weekend_rep, else: normal_rep)
    {match, reward} = Roster.reward_team_bonus(match, team, honor)
    {match, [reward, %Effects.RewardReputation{team: team, faction_id: faction(team), amount: reputation}]}
  end

  def finish(%AlteracValley{} = match, winner, now) do
    Enum.reduce([:alliance, :horde], {match, []}, fn team, {match, effects} ->
      counts = survival_counts(match, team)

      {match, rewards} =
        Enum.reduce(counts, {match, []}, fn {kind, count}, {match, effects} ->
          {match, rewards} = objective(match, team, kind, now, count)
          {match, effects ++ rewards}
        end)

      {match, weekend} = weekend_bonus(match, team, winner)
      {match, effects ++ rewards ++ weekend}
    end)
  end

  def quest_credit(%AlteracValley{} = match, team, entry) do
    match.players
    |> Map.values()
    |> Enum.filter(&(&1.status == :inside and &1.team == team))
    |> Enum.sort_by(& &1.guid)
    |> Enum.map(&%Effects.QuestKillCredit{guid: &1.guid, entry: entry})
  end

  defp duration_modifier(match, now), do: :math.pow(60, min(max(now - match.started_at, 0) / 3_600_000, 1) - 1)

  defp survival_counts(match, team) do
    towers = Enum.count(match.nodes, fn {_id, node} -> node.kind == :tower and Node.controlled_by(node) == team end)

    graves =
      Enum.count(match.nodes, fn {id, node} ->
        node.kind == :graveyard and id not in [0, 6] and Node.controlled_by(node) == team
      end)

    mines = Enum.count(match.mines, fn {_id, mine} -> mine.owner == team end)
    captain = if MapSet.member?(match.defeated_events, captain_event(team)), do: 0, else: 1

    Enum.reject(
      [surviving_tower: towers, surviving_captain: captain, graveyard: graves, mine: mines],
      &(elem(&1, 1) == 0)
    )
  end

  defp weekend_bonus(%AlteracValley{weekend?: true} = match, team, winner) do
    {match, reward} = Roster.reward_team_bonus(match, team, 1_584 + if(team == winner, do: 396, else: 0))
    {match, [reward]}
  end

  defp weekend_bonus(match, _team, _winner), do: {match, []}
  defp faction(:alliance), do: 730
  defp faction(:horde), do: 729
  defp captain_event(:alliance), do: 48
  defp captain_event(:horde), do: 49
end
