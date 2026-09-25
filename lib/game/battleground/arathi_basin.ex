defmodule ThistleTea.Game.Battleground.ArathiBasin do
  @moduledoc "Pure Arathi Basin control points, resource scoring, rewards, and graveyard selection."

  alias ThistleTea.Game.Battleground.ControlPoint
  alias ThistleTea.Game.Battleground.Defeat
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Lifecycle
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Result
  alias ThistleTea.Game.Battleground.Roster
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.WorldRef

  @enforce_keys [:world, :client_instance_id, :bracket, :template]
  defstruct [
    :world,
    :client_instance_id,
    :bracket,
    :template,
    :started_at,
    :ended_at,
    :next_resurrection_at,
    :last_resource_at,
    phase: :countdown,
    players: %{},
    nodes: %{},
    team_scores: %{alliance: 0, horde: 0},
    resource_elapsed: %{alliance: 0, horde: 0},
    honor_progress: %{alliance: 0, horde: 0},
    reputation_progress: %{alliance: 0, horde: 0},
    resurrection_queue: MapSet.new(),
    near_victory?: false,
    weekend?: false
  ]

  @teams [:alliance, :horde]
  @banner_entries [180_087, 180_088, 180_089, 180_090, 180_091, 180_058, 180_059, 180_060, 180_061]
  @node_fields [1_767, 1_782, 1_772, 1_792, 1_787]
  @neutral_fields [1_842, 1_846, 1_845, 1_844, 1_843]
  @intervals %{1 => 12_000, 2 => 9_000, 3 => 6_000, 4 => 3_000, 5 => 1_000}
  @honor [0, 41, 68, 113, 189, 198]
  @limit 2_000
  @capture_ms 60_000
  @buff_positions [
    {1_185.566, 1_184.629, -56.36329, 2.303831},
    {989.939026, 1_008.75, -42.60327, 0.8203033},
    {818.0089, 842.3543, -56.54062, 3.176533},
    {808.8463, 1_185.417, 11.92161, 5.619962},
    {1_147.091, 816.8362, -98.39896, 6.056293}
  ]

  def new(%WorldRef{} = world, client_instance_id, bracket, %Template{} = template, reservations, now, opts \\ []) do
    delay = Keyword.get(opts, :start_delay_ms, 120_000)

    match = %__MODULE__{
      world: world,
      client_instance_id: client_instance_id,
      bracket: bracket,
      template: template,
      players: Roster.new(reservations),
      nodes: Map.new(0..4, &{&1, %ControlPoint{}}),
      started_at: now + delay,
      next_resurrection_at: now + delay,
      weekend?: Keyword.get(opts, :weekend?, false)
    }

    %Result{match: match, effects: [%Effects.OperateGates{action: :close}], timers: Lifecycle.start_timers(delay)}
  end

  defdelegate enter(match, guid, return_to), to: Roster
  defdelegate reserve(match, reservations), to: Roster
  defdelegate reconnect(match, guid), to: Roster
  defdelegate queue_resurrection(match, guid), to: Roster
  defdelegate cancel_resurrection(match, guid), to: Roster
  defdelegate auto_leave_ms(match, now), to: Lifecycle
  defdelegate next_resurrection_ms(match, now), to: Lifecycle

  def disconnect(%__MODULE__{} = match, guid, _position, _dropped_guid), do: Roster.disconnect(match, guid)
  def leave(%__MODULE__{} = match, guid, _position, _dropped_guid), do: Roster.leave(match, guid)
  def carried_flag(%__MODULE__{}, _guid), do: nil

  def objectives(%__MODULE__{} = match),
    do: Map.new(match.nodes, fn {node, point} -> {node, ControlPoint.state(point)} end)

  def use_game_object(match, guid, object_guid, entry, position, now, events \\ [])

  def use_game_object(%__MODULE__{phase: :active} = match, guid, _object_guid, entry, _position, now, events)
      when entry in @banner_entries do
    with %Player{status: :inside} = player <- Map.get(match.players, guid),
         %{event1: node, event2: state} <- Enum.find(events, &(&1.event1 in 0..4)),
         %ControlPoint{} = point <- Map.get(match.nodes, node),
         true <- ControlPoint.state(point) == state do
      {:handled, assault(match, player, node, now)}
    else
      _invalid -> {:handled, %Result{match: match}}
    end
  end

  def use_game_object(%__MODULE__{} = match, _guid, _object_guid, entry, _position, _now, _events) do
    disposition = if entry in @banner_entries, do: :handled, else: :unhandled
    {disposition, %Result{match: match}}
  end

  def area_trigger(%__MODULE__{} = match, guid, trigger_id, _now) do
    case {trigger_id, Map.get(match.players, guid)} do
      {3_948, %Player{status: :inside, team: :alliance, return_to: destination}} -> {:leave, destination}
      {3_949, %Player{status: :inside, team: :horde, return_to: destination}} -> {:leave, destination}
      _other -> :unhandled
    end
  end

  def player_died(%__MODULE__{phase: :active} = match, %Defeat{} = defeat, _dropped_guid) do
    case Map.get(match.players, defeat.victim_guid) do
      %Player{status: :inside} -> %Result{match: Roster.update_death_scores(match, defeat)}
      _missing -> %Result{match: match}
    end
  end

  def player_died(%__MODULE__{} = match, %Defeat{}, _dropped_guid), do: %Result{match: match}

  def creature_died(%__MODULE__{} = match, _defeat, _now), do: %Result{match: match}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_one_minute, _now),
    do: %Result{match: match, effects: [announce(10_477)]}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_half_minute, _now),
    do: %Result{match: match, effects: [announce(10_478)]}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start, now) do
    match = %{match | phase: :active, started_at: now, last_resource_at: now}

    %Result{
      match: match,
      effects: [
        %Effects.OperateGates{action: :open},
        %Effects.DespawnGhostGates{},
        %Effects.StartBuffs{positions: @buff_positions},
        announce(10_479),
        %Effects.UpdateWorldStates{states: world_states(match)}
      ],
      timers: [status_refresh: 1_000, resources: 1_000]
    }
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:capture, node, revision}, now) do
    result = advance_resources(match, now)

    with %__MODULE__{phase: :active} = match <- result.match,
         {:captured, point} <- ControlPoint.capture(Map.fetch!(match.nodes, node), revision, now) do
      transition = update_node(match, node, point, :captured, nil)
      merge(result, transition)
    else
      _stale -> result
    end
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:banner, node, revision}, _now) do
    case Map.fetch!(match.nodes, node) do
      %ControlPoint{revision: ^revision} = point ->
        %Result{match: match, effects: [%Effects.SetEvent{event: node, state: ControlPoint.state(point)}]}

      _stale ->
        %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: :active} = match, :resources, now) do
    result = advance_resources(match, now)
    if result.match.phase == :active, do: %{result | timers: result.timers ++ [resources: 1_000]}, else: result
  end

  def handle_timer(%__MODULE__{} = match, key, now),
    do: Lifecycle.handle_timer(match, key, now, scoreboard_snapshot(match))

  def scoreboard(%__MODULE__{} = match), do: Roster.scoreboard(match, &[&1.bases_assaulted, &1.bases_defended])
  def scoreboard_snapshot(%__MODULE__{} = match), do: Lifecycle.scoreboard_snapshot(match, scoreboard(match))

  def world_states(%__MODULE__{} = match) do
    [
      {1_776, match.team_scores.alliance},
      {1_777, match.team_scores.horde},
      {1_778, controlled_count(match, :horde)},
      {1_779, controlled_count(match, :alliance)},
      {1_780, @limit},
      {1_955, 1_800},
      {1_861, 2}
      | Enum.flat_map(0..4, &node_world_states(match, &1))
    ]
  end

  def graveyard(%__MODULE__{phase: :active} = match, team, {x, y, _z}) do
    match.nodes
    |> Enum.filter(fn {_node, point} -> ControlPoint.controlled_by(point) == team end)
    |> Enum.flat_map(fn {node, _point} ->
      case Map.get(match.template.node_graveyards, node) do
        nil -> []
        location -> [location]
      end
    end)
    |> Enum.min_by(fn {gx, gy, _gz, _orientation} -> (gx - x) ** 2 + (gy - y) ** 2 end, fn ->
      Lifecycle.team_graveyard(match.template, team)
    end)
  end

  def graveyard(%__MODULE__{phase: :countdown, template: template}, :alliance, _position), do: template.alliance_start
  def graveyard(%__MODULE__{phase: :countdown, template: template}, :horde, _position), do: template.horde_start
  def graveyard(%__MODULE__{} = match, team, _position), do: Lifecycle.team_graveyard(match.template, team)

  defp assault(match, player, node, now) do
    result = advance_resources(match, now)

    if result.match.phase == :active do
      point = Map.fetch!(result.match.nodes, node)

      case ControlPoint.assault(point, player.team, now, @capture_ms) do
        {:unchanged, _point} -> result
        {action, point} -> merge(result, update_node(result.match, node, point, action, player.guid))
      end
    else
      result
    end
  end

  defp update_node(match, node, point, action, actor_guid) do
    previous_state = ControlPoint.state(Map.fetch!(match.nodes, node))
    announcement = if action == :assaulted and previous_state == 0, do: :claimed, else: action
    match = %{match | nodes: Map.put(match.nodes, node, point)}
    match = credit_objective(match, actor_guid, action)
    team = point.assaulting || point.owner
    delay = if action == :assaulted, do: 1_000, else: 5_000
    capture = if action == :assaulted, do: [{{:capture, node, point.revision}, @capture_ms}], else: []

    %Result{
      match: match,
      effects:
        [
          %Effects.SetEvent{event: node, state: nil},
          %Effects.NodeAnnouncement{node: node, team: team, action: announcement, actor_guid: actor_guid},
          %Effects.PlaySound{sound_id: node_sound(point, announcement)},
          %Effects.UpdateWorldStates{states: world_states(match)}
        ] ++ quest_credit(actor_guid, node) ++ control_rewards(match, team, action),
      timers: [{{:banner, node, point.revision}, delay} | capture]
    }
  end

  defp credit_objective(match, guid, :assaulted),
    do: Roster.update_player(match, guid, &%{&1 | bases_assaulted: &1.bases_assaulted + 1})

  defp credit_objective(match, guid, :defended),
    do: Roster.update_player(match, guid, &%{&1 | bases_defended: &1.bases_defended + 1})

  defp credit_objective(match, _guid, _action), do: match
  defp quest_credit(nil, _node), do: []
  defp quest_credit(guid, node), do: [%Effects.QuestKillCredit{guid: guid, entry: 15_001 + node}]

  defp control_rewards(match, team, action) when action in [:captured, :defended] do
    case controlled_count(match, team) do
      5 -> [%Effects.TeamSpell{team: team, spell_id: 24_061}, %Effects.TeamSpell{team: team, spell_id: 24_064}]
      4 -> [%Effects.TeamSpell{team: team, spell_id: 24_061}]
      _count -> []
    end
  end

  defp control_rewards(_match, _team, _action), do: []

  defp advance_resources(match, now) do
    elapsed = max(now - match.last_resource_at, 0)
    match = %{match | last_resource_at: max(now, match.last_resource_at)}

    {match, effects} =
      Enum.reduce(@teams, {match, []}, fn team, {match, effects} ->
        {match, rewards} = score_team(match, team, elapsed)
        {match, effects ++ rewards}
      end)

    case Enum.find(@teams, &(Map.fetch!(match.team_scores, &1) >= @limit)) do
      nil -> %Result{match: match, effects: effects}
      winner -> finish(match, winner, now, effects)
    end
  end

  defp score_team(match, team, elapsed) do
    case controlled_count(match, team) do
      0 -> {match, []}
      count -> score_controlled(match, team, elapsed, count)
    end
  end

  defp score_controlled(match, team, elapsed, count) do
    interval = Map.fetch!(@intervals, count)
    accumulated = Map.fetch!(match.resource_elapsed, team) + elapsed
    per_tick = if count == 5, do: 30, else: 10
    remaining_ticks = div(@limit - Map.fetch!(match.team_scores, team) + per_tick - 1, per_tick)
    ticks = min(div(accumulated, interval), remaining_ticks)
    match = %{match | resource_elapsed: Map.put(match.resource_elapsed, team, accumulated - ticks * interval)}

    if ticks == 0 do
      {match, []}
    else
      points = ticks * per_tick
      score = min(Map.fetch!(match.team_scores, team) + points, @limit)
      match = %{match | team_scores: Map.put(match.team_scores, team, score)}
      {match, rewards} = resource_rewards(match, team, points)
      {match, announcement} = near_victory(match, team, score)
      {match, [%Effects.UpdateWorldStates{states: [{resource_field(team), score}]} | rewards ++ announcement]}
    end
  end

  defp resource_rewards(match, team, points) do
    honor_total = Map.fetch!(match.honor_progress, team) + points
    reputation_total = Map.fetch!(match.reputation_progress, team) + points
    honor_interval = if match.weekend?, do: 200, else: 330
    reputation_interval = if match.weekend?, do: 150, else: 200

    match = %{
      match
      | honor_progress: Map.put(match.honor_progress, team, rem(honor_total, honor_interval)),
        reputation_progress: Map.put(match.reputation_progress, team, rem(reputation_total, reputation_interval))
    }

    {match, honor} = Roster.reward_team_bonus(match, team, div(honor_total, honor_interval) * honor_amount(match))
    reputation = div(reputation_total, reputation_interval) * 10
    honor_effects = if honor.amount > 0, do: [honor], else: []

    rep_effects =
      if reputation > 0,
        do: [%Effects.RewardReputation{team: team, faction_id: faction(team), amount: reputation}],
        else: []

    {match, honor_effects ++ rep_effects}
  end

  defp near_victory(%__MODULE__{near_victory?: false} = match, team, score) when score > 1_800 do
    {text, sound} = if team == :alliance, do: {10_598, 8_457}, else: {10_599, 8_456}
    {%{match | near_victory?: true}, [announce(text), %Effects.PlaySound{sound_id: sound}]}
  end

  defp near_victory(match, _team, _score), do: {match, []}

  defp finish(match, winner, now, effects) do
    bonus = honor_amount(match) * if(match.weekend?, do: 2, else: 1)
    {match, reward} = Roster.reward_team_bonus(match, winner, bonus)
    text = if winner == :alliance, do: 10_633, else: 10_634
    Lifecycle.finish(match, winner, now, effects ++ [reward, announce(text), %Effects.StopBuffs{}], scoreboard(match))
  end

  defp controlled_count(match, team),
    do: Enum.count(match.nodes, fn {_node, point} -> ControlPoint.controlled_by(point) == team end)

  defp honor_amount(match), do: Enum.at(@honor, match.bracket, 0)
  defp faction(:alliance), do: 509
  defp faction(:horde), do: 510
  defp resource_field(:alliance), do: 1_776
  defp resource_field(:horde), do: 1_777
  defp announce(id), do: %Effects.Announce{broadcast_text_id: id, audience: :neutral}

  defp node_sound(%ControlPoint{}, :claimed), do: 8_192
  defp node_sound(%ControlPoint{assaulting: :alliance}, :assaulted), do: 8_212
  defp node_sound(%ControlPoint{assaulting: :horde}, :assaulted), do: 8_174
  defp node_sound(%ControlPoint{owner: :alliance}, _action), do: 8_173
  defp node_sound(%ControlPoint{owner: :horde}, _action), do: 8_213

  defp node_world_states(match, node) do
    state = ControlPoint.state(Map.fetch!(match.nodes, node))
    base = Enum.at(@node_fields, node)

    fields =
      for {status, offset} <- [{1, 2}, {2, 3}, {3, 0}, {4, 1}], do: {base + offset, if(state == status, do: 1, else: 0)}

    [{Enum.at(@neutral_fields, node), if(state == 0, do: 1, else: 0)} | fields]
  end

  defp merge(%Result{} = prior, %Result{} = next),
    do: %{next | effects: prior.effects ++ next.effects, timers: prior.timers ++ next.timers}
end
