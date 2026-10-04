defmodule ThistleTea.Game.Core.Battleground.AlteracValley.Offering do
  @moduledoc "Team offerings and the once-per-match departure of Ivus's and Lokholar's summoners."

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Battleground.Result

  defstruct count: 0, launched?: false

  @goal 200
  @script_route 5
  @horde_call "Soldiers of Frostwolf, come to my aid! The Ice Lord has granted us his protection. He's accepted the offering! The time has come to unleash him upon the Stormpike Army!"

  def all, do: %{alliance: %__MODULE__{}, horde: %__MODULE__{}}

  def contribute(%AlteracValley{phase: :active} = match, guid, quest_id) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         {^team, amount} <- quest(quest_id) do
      previous = Map.fetch!(match.offerings, team)

      updated = %{
        previous
        | count: previous.count + amount,
          launched?: previous.launched? or previous.count + amount >= @goal
      }

      match = %{match | offerings: Map.put(match.offerings, team, updated)}
      reputation = %Effects.RewardReputation{team: team, faction_id: faction(team), amount: amount}
      departure = if updated.launched? and not previous.launched?, do: [launch(team)], else: []
      %Result{match: match, effects: [reputation | departure]}
    else
      _ineligible -> %Result{match: match}
    end
  end

  def contribute(%AlteracValley{} = match, _guid, _quest_id), do: %Result{match: match}

  def gossip(match, guid, entry, view \\ :root)

  def gossip(%AlteracValley{phase: :active} = match, guid, entry, view) do
    with %Player{status: :inside, team: team} <- Map.get(match.players, guid),
         ^team <- summoner_team(entry) do
      menu(Map.fetch!(match.offerings, team), team, view)
    else
      _ineligible -> nil
    end
  end

  def gossip(%AlteracValley{}, _guid, _entry, _view), do: nil

  def interact(match, guid, entry, :offering_status) do
    case gossip(match, guid, entry, :offering_status) do
      nil -> {:unhandled, %Result{match: match}}
      menu -> {{:menu, menu}, %Result{match: match}}
    end
  end

  def interact(match, _guid, _entry, _action), do: {:unhandled, %Result{match: match}}

  def summoner_team(13_442), do: :alliance
  def summoner_team(13_236), do: :horde
  def summoner_team(_entry), do: nil

  defp quest(7_386), do: {:alliance, 5}
  defp quest(6_881), do: {:alliance, 1}
  defp quest(7_385), do: {:horde, 5}
  defp quest(6_801), do: {:horde, 1}
  defp quest(_id), do: nil
  defp faction(:alliance), do: 730
  defp faction(:horde), do: 729
  defp summoner(:alliance), do: 13_442
  defp summoner(:horde), do: 13_236

  defp menu(%__MODULE__{count: count}, team, :offering_status),
    do: %{text_id: status_text(team, progress(count)), options: []}

  defp menu(%__MODULE__{launched?: true, count: count}, team, :root),
    do: %{text_id: status_text(team, progress(count)), options: []}

  defp menu(%__MODULE__{count: count}, team, :root) do
    option = %{id: 0, text_id: status_option(team, progress(count)), action: :offering_status}
    %{text_id: greeting_text(team), options: [option]}
  end

  defp menu(%__MODULE__{}, _team, _view), do: nil
  defp progress(count) when count >= 160, do: 2
  defp progress(count) when count >= 100, do: 1
  defp progress(_count), do: 0
  defp status_text(:alliance, progress), do: 6_175 + progress
  defp status_text(:horde, progress), do: 6_098 + progress
  defp status_option(:alliance, progress), do: 8_757 + progress * 2
  defp status_option(:horde, progress), do: 8_641 + progress * 2
  defp greeting_text(:alliance), do: 6_174
  defp greeting_text(:horde), do: 6_093

  defp launch(team) do
    %Effects.RunCreatureScript{
      creature_entry: summoner(team),
      steps: [call(team), %ScriptStep{command: :start_waypoints, datalong: @script_route}]
    }
  end

  defp call(:alliance), do: %ScriptStep{command: :talk, dataint: 8_732}

  defp call(:horde),
    do: %ScriptStep{command: :talk, texts: [%{text: @horde_call, chat_type: :yell, language: 0, emote_id: 0}]}
end
