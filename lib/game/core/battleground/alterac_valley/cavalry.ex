defmodule ThistleTea.Game.Core.Battleground.AlteracValley.Cavalry do
  @moduledoc "Team hide and mount contributions, stable displays, and serialized cavalry launch eligibility."

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Battleground.Result

  defstruct hides: 0, mounts: 0, phase: :ready

  @commanders %{13_577 => :alliance, 13_441 => :horde}
  @quests %{
    7_026 => {:alliance, :hides},
    7_027 => {:alliance, :mounts},
    7_002 => {:horde, :hides},
    7_001 => {:horde, :mounts}
  }

  def all, do: %{alliance: %__MODULE__{}, horde: %__MODULE__{}}
  def commander_team(entry), do: Map.get(@commanders, entry)
  def broadcast_text_ids, do: [8_903]

  def contribute(%AlteracValley{phase: :active} = match, guid, quest_id) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {^team, resource} <- Map.get(@quests, quest_id) do
      cavalry = Map.fetch!(match.cavalry, team)
      updated = add(cavalry, resource)
      match = %{match | cavalry: Map.put(match.cavalry, team, updated)}
      reputation = %Effects.RewardReputation{team: team, faction_id: faction(team), amount: 1}
      %Result{match: match, effects: [reputation | stable_events(updated, team, resource)]}
    else
      _ineligible -> %Result{match: match}
    end
  end

  def contribute(%AlteracValley{} = match, _guid, _quest_id), do: %Result{match: match}

  def gossip(%AlteracValley{phase: :active} = match, guid, entry, standing)
      when is_integer(standing) and standing >= 9_000 do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- commander_team(entry),
         %__MODULE__{phase: :ready, hides: hides, mounts: mounts} when hides >= 25 and mounts >= 25 <-
           Map.get(match.cavalry, team) do
      %{text_id: 68, options: [%{id: 0, text_id: 8_903, action: :launch_cavalry_attack}]}
    else
      _ineligible -> nil
    end
  end

  def gossip(%AlteracValley{}, _guid, _entry, _standing), do: nil

  def interact(match, guid, entry, :launch_cavalry_attack, standing) do
    case gossip(match, guid, entry, standing) do
      nil ->
        {:close, %Result{match: match}}

      _menu ->
        team = commander_team(entry)
        match = %{match | cavalry: Map.put(match.cavalry, team, %__MODULE__{phase: :marching})}

        launch = %Effects.RunCreatureScript{
          creature_entry: entry,
          steps: [%ScriptStep{command: :send_script_event, datalong: 1}]
        }

        {:close, %Result{match: match, effects: reset_stables(team) ++ [launch]}}
    end
  end

  def interact(match, _guid, _entry, _action, _standing), do: {:unhandled, %Result{match: match}}

  def creature_event(%AlteracValley{phase: :active} = match, entry, event) when event in [0, 1] do
    case commander_team(entry) do
      nil ->
        %Result{match: match}

      team ->
        cavalry = Map.fetch!(match.cavalry, team)
        phase = if event == 0, do: :ready, else: :dead
        %Result{match: %{match | cavalry: Map.put(match.cavalry, team, %{cavalry | phase: phase})}}
    end
  end

  def creature_event(%AlteracValley{} = match, _entry, _event), do: %Result{match: match}

  defp add(%__MODULE__{} = cavalry, :hides), do: %{cavalry | hides: cavalry.hides + 1}
  defp add(%__MODULE__{} = cavalry, :mounts), do: %{cavalry | mounts: cavalry.mounts + 1}

  defp stable_events(%__MODULE__{mounts: mounts}, team, :mounts) when rem(mounts, 25) in [5, 10, 15, 20] do
    event = 90 + team_index(team) + div(rem(mounts, 25) - 5, 5) * 2
    [%Effects.SetEvent{event: event, state: 0}]
  end

  defp stable_events(%__MODULE__{}, _team, _resource), do: []

  defp reset_stables(team), do: Enum.map([90, 92, 94, 96], &%Effects.SetEvent{event: &1 + team_index(team), state: 2})
  defp team_index(:alliance), do: 0
  defp team_index(:horde), do: 1
  defp faction(:alliance), do: 730
  defp faction(:horde), do: 729
end
