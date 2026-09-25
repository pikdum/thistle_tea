defmodule ThistleTea.Game.Battleground.AlteracValley do
  @moduledoc "Pure Alterac Valley match lifecycle, contested objectives, creature victories, and resurrection geography."

  alias ThistleTea.Game.Battleground.AlteracValley.Creatures
  alias ThistleTea.Game.Battleground.AlteracValley.Mine
  alias ThistleTea.Game.Battleground.AlteracValley.Node
  alias ThistleTea.Game.Battleground.AlteracValley.Rewards
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
    phase: :countdown,
    players: %{},
    nodes: %{},
    mines: %{},
    defeated_events: MapSet.new(),
    defeated_incarnations: MapSet.new(),
    armor_upgrades: %{alliance: 0, horde: 0},
    team_scores: %{alliance: 0, horde: 0},
    resurrection_queue: MapSet.new(),
    weekend?: false
  ]

  @banner_entries [178_364, 178_365, 178_925, 178_940, 178_943, 179_286, 179_287, 179_435, 180_418]

  def new(%WorldRef{} = world, client_instance_id, bracket, %Template{} = template, reservations, now, opts \\ []) do
    delay = Keyword.get(opts, :start_delay_ms, 120_000)

    match = %__MODULE__{
      world: world,
      client_instance_id: client_instance_id,
      bracket: bracket,
      template: template,
      started_at: now + delay,
      next_resurrection_at: now + delay,
      players: Roster.new(reservations),
      nodes: Node.all(),
      mines: Mine.all(),
      weekend?: Keyword.get(opts, :weekend?, false)
    }

    %Result{match: match, effects: [%Effects.OperateGates{action: :close}], timers: Lifecycle.start_timers(delay)}
  end

  def initial_events do
    nodes = Enum.flat_map(Node.all(), fn {id, node} -> [{id, Node.event_state(node)} | Node.defender_events(node)] end)
    mines = Enum.flat_map(Mine.all(), fn {_id, mine} -> Mine.events(mine) end)

    creatures =
      for event <- [48, 49] ++ Enum.to_list(52..62) ++ Enum.to_list(65..69) ++ [100, 101, 253, 254], do: {event, 0}

    resources = for event <- Enum.to_list(80..87) ++ Enum.to_list(90..97), do: {event, 2}
    Map.new(nodes ++ mines ++ creatures ++ resources)
  end

  defdelegate enter(match, guid, return_to), to: Roster
  defdelegate reserve(match, reservations), to: Roster
  defdelegate reconnect(match, guid), to: Roster
  defdelegate queue_resurrection(match, guid), to: Roster
  defdelegate cancel_resurrection(match, guid), to: Roster
  defdelegate auto_leave_ms(match, now), to: Lifecycle
  defdelegate next_resurrection_ms(match, now), to: Lifecycle
  defdelegate creature_died(match, defeat, now), to: Creatures, as: :defeated

  def disconnect(%__MODULE__{} = match, guid, _position, _dropped_guid), do: Roster.disconnect(match, guid)
  def leave(%__MODULE__{} = match, guid, _position, _dropped_guid), do: Roster.leave(match, guid)
  def carried_flag(%__MODULE__{}, _guid), do: nil

  def objectives(%__MODULE__{} = match) do
    %{nodes: Map.new(match.nodes, fn {id, node} -> {id, Node.event_state(node)} end), mines: match.mines}
  end

  def use_game_object(match, guid, object_guid, entry, position, now, events \\ [])

  def use_game_object(%__MODULE__{phase: :active} = match, guid, _object_guid, entry, _position, now, events)
      when entry in @banner_entries do
    with %Player{status: :inside} = player <- Map.get(match.players, guid),
         %{event1: id, event2: state} <- Enum.find(events, &(&1.event1 in 0..14)),
         %Node{} = node <- Map.get(match.nodes, id),
         true <- Node.event_state(node) == state,
         {action, node} when action != :unchanged <- Node.assault(node, player.team, now) do
      {:handled, update_node(match, node, action, guid, now)}
    else
      _ineligible -> {:handled, %Result{match: match}}
    end
  end

  def use_game_object(%__MODULE__{} = match, _guid, _object_guid, entry, _position, _now, _events) do
    {if(entry in @banner_entries, do: :handled, else: :unhandled), %Result{match: match}}
  end

  def area_trigger(%__MODULE__{} = match, guid, trigger_id, _now) do
    case {trigger_id, Map.get(match.players, guid)} do
      {2_608, %Player{status: :inside, team: :alliance, return_to: destination}} -> {:leave, destination}
      {2_606, %Player{status: :inside, team: :horde, return_to: destination}} -> {:leave, destination}
      _other -> :unhandled
    end
  end

  def player_died(%__MODULE__{phase: :active} = match, %Defeat{} = defeat, _dropped_guid) do
    case Map.get(match.players, defeat.victim_guid) do
      %Player{status: :inside} -> %Result{match: Roster.update_death_scores(match, defeat)}
      _ineligible -> %Result{match: match}
    end
  end

  def player_died(%__MODULE__{} = match, %Defeat{}, _dropped_guid), do: %Result{match: match}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_one_minute, _now),
    do: %Result{match: match, effects: [announce(10_638)]}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_half_minute, _now),
    do: %Result{match: match, effects: [announce(10_639)]}

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start, now) do
    match = %{match | phase: :active, started_at: now}

    %Result{
      match: match,
      effects: [
        %Effects.OperateGates{action: :open},
        %Effects.DespawnGhostGates{},
        announce(10_640),
        %Effects.UpdateWorldStates{states: world_states(match)},
        Creatures.schedule_captain_buff(:alliance),
        Creatures.schedule_captain_buff(:horde)
      ],
      timers: [status_refresh: 1_000]
    }
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:capture, id, revision}, now) do
    with %Node{} = node <- Map.get(match.nodes, id),
         {:captured, node} <- Node.capture(node, revision, now) do
      update_node(match, node, :captured, nil, now)
    else
      _stale -> %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:banner, id, revision}, _now) do
    case Map.get(match.nodes, id) do
      %Node{point: %{revision: ^revision}} = node ->
        %Result{match: match, effects: [%Effects.SetEvent{event: id, state: Node.event_state(node)}]}

      _stale ->
        %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:mine_reclaim, id, revision}, now) do
    with %Mine{} = mine <- Map.get(match.mines, id),
         {:reclaimed, mine} <- Mine.reclaim(mine, revision, now) do
      Creatures.update_mine(match, mine)
    else
      _stale -> %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: :active} = match, {:captain_buff, team}, _now),
    do: Creatures.captain_buff(match, team)

  def handle_timer(%__MODULE__{} = match, key, now),
    do: Lifecycle.handle_timer(match, key, now, scoreboard_snapshot(match))

  def scoreboard(%__MODULE__{} = match) do
    Roster.scoreboard(
      match,
      &[
        &1.graveyards_assaulted,
        &1.graveyards_defended,
        &1.towers_assaulted,
        &1.towers_defended,
        &1.secondary_objectives
      ]
    )
  end

  def scoreboard_snapshot(%__MODULE__{} = match), do: Lifecycle.scoreboard_snapshot(match, scoreboard(match))

  def world_states(%__MODULE__{} = match) do
    Enum.flat_map(Enum.sort(match.nodes), fn {_id, node} -> Node.world_states(node) end) ++
      Enum.flat_map(Enum.sort(match.mines), fn {_id, mine} -> Mine.world_states(mine) end)
  end

  def graveyard(%__MODULE__{phase: :active} = match, team, {x, y, _z}) do
    locations =
      match.nodes
      |> Enum.filter(fn {_id, node} -> node.kind == :graveyard and Node.controlled_by(node) == team end)
      |> Enum.map(fn {id, _node} -> Map.get(match.template.node_graveyards, id) end)

    [Lifecycle.team_graveyard(match.template, team) | locations]
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(fn {gx, gy, _gz, _o} -> (gx - x) ** 2 + (gy - y) ** 2 end, fn -> nil end)
  end

  def graveyard(%__MODULE__{} = match, team, _position), do: Lifecycle.team_graveyard(match.template, team)

  def supply_allowed?(%__MODULE__{phase: :active} = match, guid, entry) when entry in [178_784, 178_785] do
    case Map.get(match.players, guid) do
      %Player{status: :inside, team: team} ->
        Mine.supply_allowed?(Map.fetch!(match.mines, if(entry == 178_785, do: 0, else: 1)), team)

      _ineligible ->
        false
    end
  end

  def supply_allowed?(%__MODULE__{}, _guid, _entry), do: false

  defp update_node(match, node, action, guid, now) do
    match = %{match | nodes: Map.put(match.nodes, node.id, node)}
    match = credit_node(match, guid, node.kind, action)
    team = node.point.assaulting || node.point.owner
    {match, rewards} = node_rewards(match, node, action, now)
    delay = if action == :assaulted, do: 1_000, else: 5_000
    captures = if action == :assaulted, do: [{{:capture, node.id, node.point.revision}, Node.capture_ms()}], else: []

    %Result{
      match: match,
      effects:
        [
          %Effects.SetEvent{event: node.id, state: nil},
          %Effects.ObjectiveAnnouncement{name: node.name, kind: node.kind, team: team, action: action},
          %Effects.PlaySound{sound_id: node_sound(node, action)},
          %Effects.UpdateWorldStates{states: Node.world_states(node)}
        ] ++ defender_effects(match, node, action) ++ rewards,
      timers: [{{:banner, node.id, node.point.revision}, delay} | captures]
    }
  end

  defp defender_effects(match, node, action) do
    upgrade = Map.get(match.armor_upgrades, node.point.owner, 0)

    Enum.map(Node.defender_events(node, upgrade), fn {event, state} ->
      if action == :assaulted,
        do: %Effects.StopEventRespawns{event: event},
        else: %Effects.SetEvent{event: event, state: state}
    end)
  end

  defp node_rewards(match, %Node{kind: :tower, point: point}, :captured, now) do
    {match, rewards} = Rewards.objective(match, point.owner, :tower, now)
    {match, rewards ++ Rewards.quest_credit(match, point.owner, 13_778)}
  end

  defp node_rewards(match, %Node{kind: :graveyard, point: point}, :captured, _now),
    do: {match, Rewards.quest_credit(match, point.owner, 13_756)}

  defp node_rewards(match, _node, _action, _now), do: {match, []}

  defp credit_node(match, guid, :graveyard, :assaulted),
    do: Roster.update_player(match, guid, &%{&1 | graveyards_assaulted: &1.graveyards_assaulted + 1})

  defp credit_node(match, guid, :graveyard, :defended),
    do: Roster.update_player(match, guid, &%{&1 | graveyards_defended: &1.graveyards_defended + 1})

  defp credit_node(match, guid, :tower, :assaulted),
    do: Roster.update_player(match, guid, &%{&1 | towers_assaulted: &1.towers_assaulted + 1})

  defp credit_node(match, guid, :tower, :defended),
    do: Roster.update_player(match, guid, &%{&1 | towers_defended: &1.towers_defended + 1})

  defp credit_node(match, _guid, _kind, _action), do: match
  defp node_sound(%Node{point: %{assaulting: :alliance}}, :assaulted), do: 8_212
  defp node_sound(%Node{}, :assaulted), do: 8_174
  defp node_sound(%Node{kind: :tower}, :defended), do: 8_192
  defp node_sound(%Node{point: %{owner: :alliance}}, _action), do: 8_173
  defp node_sound(%Node{}, _action), do: 8_213
  defp announce(id), do: %Effects.Announce{broadcast_text_id: id, audience: :neutral}
end
