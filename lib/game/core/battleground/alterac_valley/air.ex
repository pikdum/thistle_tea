defmodule ThistleTea.Game.Core.Battleground.AlteracValley.Air do
  @moduledoc "Wing commander rescues and each fleet's supply stockpile in an Alterac Valley match."

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Battleground.Result

  defstruct phase: :prisoner, count: 0, launched?: false

  @commanders %{
    13_179 => {:horde, 6_825, 90, 1},
    13_180 => {:horde, 6_826, 60, 2},
    13_181 => {:horde, 6_827, 30, 5},
    13_438 => {:alliance, 6_942, 90, 1},
    13_439 => {:alliance, 6_941, 60, 2},
    13_437 => {:alliance, 6_943, 30, 5}
  }

  @launch_texts %{
    13_179 => 10_341,
    13_180 => 10_343,
    13_181 => 10_346,
    13_438 => 10_351,
    13_439 => 10_353,
    13_437 => 10_349
  }

  def all, do: Map.new(@commanders, fn {entry, _fleet} -> {entry, %__MODULE__{}} end)
  def entries, do: Map.keys(@commanders)
  def commander?(entry), do: Map.has_key?(@commanders, entry)
  def broadcast_text_ids, do: Map.values(@launch_texts)

  def contribute(%AlteracValley{phase: :active} = match, guid, quest_id) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {entry, {^team, ^quest_id, goal, reputation}} <- Enum.find(@commanders, &(elem(elem(&1, 1), 1) == quest_id)),
         %__MODULE__{phase: :ready} = fleet <- Map.get(match.air, entry) do
      updated = %{fleet | count: fleet.count + 1}
      match = %{match | air: Map.put(match.air, entry, updated)}
      reward = %Effects.RewardReputation{team: team, faction_id: faction(team), amount: reputation}
      announcement = if fleet.count < goal and updated.count >= goal, do: [ready(entry, team)], else: []
      %Result{match: match, effects: [reward | announcement]}
    else
      _ineligible -> %Result{match: match}
    end
  end

  def contribute(%AlteracValley{} = match, _guid, _quest_id), do: %Result{match: match}

  def begin_rescue(%AlteracValley{phase: :active} = match, guid, entry) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {^team, _quest, _goal, _reputation} <- Map.get(@commanders, entry),
         %__MODULE__{phase: :ready} <- Map.get(match.air, entry) do
      {:unhandled, %Result{match: match}}
    else
      _not_home -> start_rescue(match, guid, entry)
    end
  end

  def begin_rescue(%AlteracValley{} = match, _guid, _entry), do: {:close, %Result{match: match}}

  def gossip(%AlteracValley{phase: :active} = match, guid, entry, standing) when standing >= 0 do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {^team, _quest, goal, _reputation} <- Map.get(@commanders, entry),
         %__MODULE__{phase: :ready, count: count, launched?: false} when count >= goal <- Map.get(match.air, entry) do
      %{text_id: 68, options: [%{id: 0, text_id: Map.fetch!(@launch_texts, entry), action: :launch_air_attack}]}
    else
      _ineligible -> nil
    end
  end

  def gossip(%AlteracValley{}, _guid, _entry, _standing), do: nil

  def interact(match, guid, entry, :launch_air_attack, standing) do
    case gossip(match, guid, entry, standing) do
      nil ->
        {:close, %Result{match: match}}

      _menu ->
        fleet = Map.fetch!(match.air, entry)
        match = %{match | air: Map.put(match.air, entry, %{fleet | launched?: true})}

        effect = %Effects.RunCreatureScript{
          creature_entry: entry,
          steps: [%ScriptStep{command: :send_script_event, datalong: 2}]
        }

        {:close, %Result{match: match, effects: [effect]}}
    end
  end

  def interact(match, _guid, _entry, _action, _standing), do: {:unhandled, %Result{match: match}}

  defp start_rescue(match, guid, entry) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {^team, _quest, _goal, _reputation} <- Map.get(@commanders, entry),
         %__MODULE__{phase: :prisoner} = fleet <- Map.get(match.air, entry) do
      match = %{match | air: Map.put(match.air, entry, %{fleet | phase: :returning})}
      step = %ScriptStep{command: :send_script_event, datalong: 1}
      effect = %Effects.RunCreatureScript{creature_entry: entry, steps: [step]}
      {:close, %Result{match: match, effects: [effect]}}
    else
      _ineligible -> {:close, %Result{match: match}}
    end
  end

  def creature_event(%AlteracValley{phase: :active} = match, entry, event) do
    case {Map.get(match.air, entry), event} do
      {%__MODULE__{phase: :returning} = fleet, 1} -> put_fleet(match, entry, %{fleet | phase: :ready})
      {%__MODULE__{} = fleet, 0} -> put_fleet(match, entry, %{fleet | phase: :prisoner})
      _other -> %Result{match: match}
    end
  end

  def creature_event(%AlteracValley{} = match, _entry, _event), do: %Result{match: match}

  defp put_fleet(match, entry, fleet), do: %Result{match: %{match | air: Map.put(match.air, entry, fleet)}}
  defp faction(:alliance), do: 730
  defp faction(:horde), do: 729

  defp ready(entry, team) do
    faction = if team == :alliance, do: "Stormpike", else: "the Horde"

    %Effects.RunCreatureScript{
      creature_entry: entry,
      steps: [
        %ScriptStep{
          command: :talk,
          texts: [
            %{
              text: "Soldiers of #{faction}, come to my aid! The beacon must be planted.",
              chat_type: :yell,
              language: 0,
              emote_id: 0
            }
          ]
        }
      ]
    }
  end
end
