defmodule ThistleTea.Game.Battleground.AlteracValley.Creatures do
  @moduledoc "Alterac creature objective transitions, mine captures, and living captain buffs."

  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Mine
  alias ThistleTea.Game.Battleground.AlteracValley.Rewards
  alias ThistleTea.Game.Battleground.CreatureDefeat
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Lifecycle
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Result
  alias ThistleTea.Game.Battleground.Roster

  @alliance_events [48, 52, 53, 54, 55, 61, 66, 68]
  @horde_events [49, 56, 57, 58, 59, 62, 67, 69]
  @objective_events [46, 47] ++ @alliance_events ++ @horde_events
  @captain_delays [120_000, 180_000, 240_000, 300_000, 360_000]

  def defeated(%AlteracValley{phase: :active} = match, %CreatureDefeat{} = defeat, now) do
    incarnation = {defeat.victim_guid, defeat.incarnation_id}

    with false <- MapSet.member?(match.defeated_incarnations, incarnation),
         %Player{status: :inside, team: team} <- Map.get(match.players, defeat.killer_guid),
         %{event1: event, event2: state} <- Enum.find(defeat.bindings, &(&1.event1 in @objective_events)),
         true <- eligible?(match, event, state, team) do
      match = %{match | defeated_incarnations: MapSet.put(match.defeated_incarnations, incarnation)}
      match = credit_defeat(match, event, defeat.killer_guid)
      defeat_objective(match, event, team, now)
    else
      _ineligible -> %Result{match: match}
    end
  end

  def defeated(%AlteracValley{} = match, %CreatureDefeat{}, _now), do: %Result{match: match}

  def update_mine(%AlteracValley{} = match, %Mine{} = mine) do
    match = %{match | mines: Map.put(match.mines, mine.id, mine)}
    events = Enum.map(Mine.events(mine), fn {event, state} -> %Effects.SetEvent{event: event, state: state} end)
    name = if mine.id == 0, do: "Irondeep Mine", else: "Coldtooth Mine"

    rewards =
      if mine.owner do
        [
          %Effects.PlaySound{sound_id: if(mine.owner == :alliance, do: 8_173, else: 8_213)},
          %Effects.ObjectiveAnnouncement{name: name, kind: :mine, team: mine.owner, action: :captured}
          | Rewards.quest_credit(match, mine.owner, 13_796)
        ]
      else
        [%Effects.ObjectiveAnnouncement{name: name, kind: :mine, team: nil, action: :reclaimed}]
      end

    %Result{
      match: match,
      effects: events ++ [%Effects.UpdateWorldStates{states: Mine.world_states(mine)}] ++ rewards,
      timers: if(mine.owner, do: [{{:mine_reclaim, mine.id, mine.revision}, Mine.reclaim_ms()}], else: [])
    }
  end

  def captain_buff(%AlteracValley{} = match, team) when team in [:alliance, :horde] do
    event = if team == :alliance, do: 48, else: 49

    if MapSet.member?(match.defeated_events, event) do
      %Result{match: match}
    else
      {name, spell, sound} =
        if team == :alliance, do: {"Balinda Stonehearth", 23_693, 8_232}, else: {"Galvangar", 22_751, 8_333}

      %Result{
        match: match,
        effects: [
          %Effects.TeamSpell{team: team, spell_id: spell},
          %Effects.ObjectiveAnnouncement{name: name, kind: :captain, team: team, action: :buff},
          %Effects.PlaySound{sound_id: sound},
          schedule_captain_buff(team)
        ]
      }
    end
  end

  def schedule_captain_buff(team), do: %Effects.ScheduleTimer{key: {:captain_buff, team}, delays: @captain_delays}

  defp eligible?(match, event, state, team) when event in [46, 47] do
    mine = Map.fetch!(match.mines, event - 46)
    Mine.event_state(mine) == state and mine.owner != team
  end

  defp eligible?(match, event, 0, team) do
    enemy_event? = (team == :alliance and event in @horde_events) or (team == :horde and event in @alliance_events)
    enemy_event? and not MapSet.member?(match.defeated_events, event)
  end

  defp eligible?(_match, _event, _state, _team), do: false

  defp defeat_objective(match, event, team, now) when event in [46, 47] do
    {:captured, mine} = Mine.capture(Map.fetch!(match.mines, event - 46), team, now)
    update_mine(match, mine)
  end

  defp defeat_objective(match, event, team, now) when event in [61, 62] do
    match = record_event(match, event)
    {match, general} = Rewards.objective(match, team, :general, now)
    {match, surviving} = Rewards.finish(match, team, now)

    effects = [
      %Effects.StopEventRespawns{event: event},
      %Effects.TeamSpell{team: team, spell_id: 23_658},
      %Effects.Announce{broadcast_text_id: if(team == :alliance, do: 7_335, else: 7_336), audience: :neutral}
    ]

    Lifecycle.finish(match, team, now, effects ++ general ++ surviving, AlteracValley.scoreboard(match))
  end

  defp defeat_objective(match, event, team, now) when event in [48, 49] do
    match = record_event(match, event)
    {match, rewards} = Rewards.objective(match, team, :captain, now)

    %Result{
      match: match,
      effects: [%Effects.StopEventRespawns{event: event}, %Effects.SetEvent{event: event + 15, state: 0} | rewards]
    }
  end

  defp defeat_objective(match, event, team, now) when event in 52..59 do
    match = record_event(match, event)
    {match, rewards} = Rewards.objective(match, team, :commander, now)

    quest =
      case event do
        54 -> Rewards.quest_credit(match, team, 13_320)
        57 -> Rewards.quest_credit(match, team, 13_154)
        _other -> []
      end

    %Result{match: match, effects: [%Effects.StopEventRespawns{event: event} | rewards ++ quest]}
  end

  defp defeat_objective(match, event, team, _now) when event in [66, 67] do
    match = record_event(match, event)
    entry = if event == 66, do: 13_598, else: 13_597
    landmines = if event == 66, do: 100, else: 101

    %Result{
      match: match,
      effects: [
        %Effects.StopEventRespawns{event: event},
        %Effects.SetEvent{event: landmines, state: nil} | Rewards.quest_credit(match, team, entry)
      ]
    }
  end

  defp defeat_objective(match, event, team, now) when event in [68, 69] do
    {match, rewards} = Rewards.objective(match, team, :commander, now)
    %Result{match: match, effects: rewards}
  end

  defp credit_defeat(match, event, guid) when event in [46, 47],
    do: Roster.update_player(match, guid, &%{&1 | mines_captured: &1.mines_captured + 1})

  defp credit_defeat(match, event, guid) when event in [48, 49, 61, 62, 68, 69] or event in 52..59,
    do: Roster.update_player(match, guid, &%{&1 | leaders_killed: &1.leaders_killed + 1})

  defp credit_defeat(match, _event, _guid), do: match

  defp record_event(match, event), do: %{match | defeated_events: MapSet.put(match.defeated_events, event)}
end
