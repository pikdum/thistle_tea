defmodule ThistleTea.Game.Battleground.AlteracValley.Armor do
  @moduledoc "Team armor donations, blacksmith upgrade requests, and defender tier projections."

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Result

  defstruct scraps: 0, tier: 0

  def all, do: %{alliance: %__MODULE__{}, horde: %__MODULE__{}}
  def tier(%AlteracValley{} = match, team), do: stockpile(match, team).tier

  def contribute(%AlteracValley{phase: :active} = match, guid, quest_id) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- quest_team(quest_id) do
      previous = stockpile(match, team)
      updated = %{previous | scraps: previous.scraps + 20}
      match = %{match | armor: Map.put(match.armor, team, updated)}
      reputation = %Effects.RewardReputation{team: team, faction_id: faction(team), amount: 1}
      %Result{match: match, effects: crate_changes(previous, updated, team) ++ [reputation]}
    else
      _ineligible -> %Result{match: match}
    end
  end

  def contribute(%AlteracValley{} = match, _guid, _quest_id), do: %Result{match: match}

  def gossip(match, guid, entry, standing, view \\ :root)

  def gossip(%AlteracValley{phase: :active} = match, guid, entry, standing, view) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- smith_team(entry) do
      armor = stockpile(match, team)
      menu(armor, standing, view)
    else
      _ineligible -> nil
    end
  end

  def gossip(%AlteracValley{}, _guid, _entry, _standing, _view), do: nil

  def upgrade(%AlteracValley{phase: :active} = match, guid, entry, requested_tier, standing) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- smith_team(entry),
         %__MODULE__{} = armor <- stockpile(match, team),
         true <- ready?(armor, standing),
         true <- requested_tier == armor.tier + 1 do
      armor = %{armor | tier: requested_tier}
      match = %{match | armor: Map.put(match.armor, team, armor)}

      %Result{
        match: match,
        effects:
          defender_changes(match, team, requested_tier) ++
            [
              %Effects.TeamSpell{team: team, spell_id: 28_417 + requested_tier},
              %Effects.ArmorUpgrade{team: team, tier: requested_tier}
            ]
      }
    else
      _ineligible -> %Result{match: match}
    end
  end

  def upgrade(%AlteracValley{} = match, _guid, _entry, _tier, _standing), do: %Result{match: match}

  def interact(match, guid, entry, :armor_status, standing) do
    case gossip(match, guid, entry, standing, :armor_status) do
      nil -> {:unhandled, %Result{match: match}}
      menu -> {{:menu, menu}, %Result{match: match}}
    end
  end

  def interact(match, guid, entry, {:upgrade_armor, tier}, standing),
    do: {:close, upgrade(match, guid, entry, tier, standing)}

  def interact(match, _guid, _entry, _action, _standing), do: {:unhandled, %Result{match: match}}

  def smith_team(13_257), do: :alliance
  def smith_team(13_176), do: :horde
  def smith_team(_entry), do: nil

  defp quest_team(id) when id in [7_223, 6_781], do: :alliance
  defp quest_team(id) when id in [7_224, 6_741], do: :horde
  defp quest_team(_id), do: nil
  defp faction(:alliance), do: 730
  defp faction(:horde), do: 729
  defp stockpile(match, team), do: Map.get(match.armor, team, %__MODULE__{})

  defp ready?(%__MODULE__{scraps: scraps, tier: tier}, standing),
    do: tier < 3 and scraps >= (tier + 1) * 500 and standing >= 9_000

  defp menu(%__MODULE__{} = armor, _standing, :armor_status), do: %{text_id: progress_text(armor), options: []}

  defp menu(%__MODULE__{tier: 3}, _standing, :root), do: %{text_id: 6_222, options: []}

  defp menu(%__MODULE__{} = armor, standing, :root) do
    status = %{id: 0, text_id: 9_130, action: :armor_status}

    options =
      if ready?(armor, standing) do
        text_id = Enum.at([8_718, 8_719, 8_723], armor.tier)
        [status, %{id: 1, text_id: text_id, action: {:upgrade_armor, armor.tier + 1}}]
      else
        [status]
      end

    text_id =
      if armor.scraps >= (armor.tier + 1) * 500,
        do: 6_219 + armor.tier,
        else: Enum.at([6_073, 6_217, 6_218], armor.tier)

    %{text_id: text_id, options: options}
  end

  defp menu(%__MODULE__{}, _standing, _view), do: nil

  defp progress_text(%__MODULE__{tier: 3}), do: 6_222

  defp progress_text(%__MODULE__{scraps: scraps, tier: tier}) do
    remaining = (tier + 1) * 500 - scraps

    cond do
      remaining <= 0 -> 6_219 + tier
      remaining <= 100 -> Enum.at([6_778, 6_779, 6_782], tier)
      remaining < 300 -> Enum.at([6_780, 6_781, 6_783], tier)
      true -> 6_784
    end
  end

  defp crate_changes(previous, updated, team) do
    first_event = if team == :alliance, do: 80, else: 81

    for index <- 1..4, crate_state(previous, index) != crate_state(updated, index) do
      %Effects.SetEvent{event: first_event + (index - 1) * 2, state: crate_state(updated, index)}
    end
  end

  defp crate_state(%__MODULE__{scraps: scraps}, index), do: if(rem(scraps, 500) >= index * 100, do: 0, else: 2)

  defp defender_changes(match, team, tier) do
    match.nodes
    |> Enum.sort()
    |> Enum.filter(fn {_id, node} -> Node.controlled_by(node) == team end)
    |> Enum.flat_map(fn {_id, node} -> Node.defender_events(node, tier) end)
    |> Enum.map(fn {event, state} -> %Effects.SetEvent{event: event, state: state} end)
  end
end
