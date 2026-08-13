defmodule ThistleTea.Game.Battleground.WarsongGulch do
  @moduledoc """
  Pure Warsong Gulch match transitions.
  """

  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.WorldRef

  defmodule Player do
    @moduledoc false
    @enforce_keys [:guid, :name, :team]
    defstruct [
      :guid,
      :name,
      :team,
      :return_to,
      status: :invited,
      killing_blows: 0,
      honorable_kills: 0,
      deaths: 0,
      bonus_honor: 0,
      flag_captures: 0,
      flag_returns: 0
    ]
  end

  defmodule Flag do
    @moduledoc false
    defstruct state: :base, carrier: nil, dropped_guid: nil, generation: 0
  end

  defmodule Result do
    @moduledoc false
    @enforce_keys [:match]
    defstruct [:match, effects: [], timers: []]
  end

  @enforce_keys [:world, :client_instance_id, :bracket, :template]
  defstruct [
    :world,
    :client_instance_id,
    :bracket,
    :template,
    :started_at,
    :ended_at,
    :next_resurrection_at,
    :flags,
    phase: :countdown,
    players: %{},
    team_scores: %{alliance: 0, horde: 0},
    resurrection_queue: MapSet.new()
  ]

  @alliance_flag_base 179_830
  @horde_flag_base 179_831
  @alliance_flag_ground 179_785
  @horde_flag_ground 179_786
  @alliance_capture_trigger 3_646
  @horde_capture_trigger 3_647
  @alliance_exit_trigger 3_671
  @horde_exit_trigger 3_669
  @max_score 3
  @start_delay_ms 120_000
  @flag_respawn_ms 23_000
  @flag_drop_ms 10_000
  @resurrection_wave_ms 30_000
  @auto_leave_ms 120_000
  @flag_capture_honor [48, 82, 136, 226, 378, 396]
  @win_honor [24, 41, 68, 113, 189, 198]

  @world_state_flag_taken_alliance 1_545
  @world_state_flag_taken_horde 1_546
  @world_state_captures_alliance 1_581
  @world_state_captures_horde 1_582
  @world_state_captures_max 1_601
  @world_state_flag_state_horde 2_338
  @world_state_flag_state_alliance 2_339

  @sound_flag_captured_alliance 8_173
  @sound_flag_captured_horde 8_213
  @sound_flag_placed 8_232
  @sound_flag_returned 8_192
  @sound_horde_flag_picked_up 8_212
  @sound_alliance_flag_picked_up 8_174

  def new(%WorldRef{} = world, client_instance_id, bracket, %Template{} = template, reservations, now, opts \\ []) do
    start_delay_ms = Keyword.get(opts, :start_delay_ms, @start_delay_ms)

    players =
      Map.new(reservations, fn reservation ->
        player = struct(Player, reservation)
        {player.guid, player}
      end)

    match = %__MODULE__{
      world: world,
      client_instance_id: client_instance_id,
      bracket: bracket,
      template: template,
      players: players,
      flags: %{alliance: %Flag{}, horde: %Flag{}},
      started_at: now + start_delay_ms,
      next_resurrection_at: now + start_delay_ms
    }

    %Result{
      match: match,
      effects: [%Effects.OperateGates{action: :close}],
      timers: start_timers(start_delay_ms) ++ [resurrection_timer(start_delay_ms)]
    }
  end

  def enter(%__MODULE__{} = match, guid, return_to) do
    case Map.get(match.players, guid) do
      %Player{} = player ->
        player = %{player | status: :inside, return_to: return_to}
        match = put_player(match, player)
        %Result{match: match, effects: [%Effects.PlayerJoined{guid: guid}]}

      nil ->
        %Result{match: match}
    end
  end

  def reserve(%__MODULE__{phase: phase} = match, reservations) when phase in [:countdown, :active] do
    players =
      Enum.reduce(reservations, match.players, fn reservation, players ->
        player = struct(Player, reservation)
        Map.put_new(players, player.guid, player)
      end)

    %Result{match: %{match | players: players}}
  end

  def reserve(%__MODULE__{} = match, _reservations), do: %Result{match: match}

  def reconnect(%__MODULE__{} = match, guid) do
    case Map.get(match.players, guid) do
      %Player{} = player ->
        player = %{player | status: :inside}
        %Result{match: put_player(match, player), effects: [%Effects.PlayerJoined{guid: guid}]}

      nil ->
        %Result{match: match}
    end
  end

  def disconnect(%__MODULE__{} = match, guid, position, dropped_guid) do
    case Map.get(match.players, guid) do
      %Player{} = player ->
        match = put_player(match, %{player | status: :offline})
        drop_carried_flag(match, guid, position, dropped_guid)

      nil ->
        %Result{match: match}
    end
  end

  def leave(%__MODULE__{} = match, guid, position, dropped_guid) do
    result = drop_carried_flag(match, guid, position, dropped_guid)

    case Map.pop(result.match.players, guid) do
      {nil, _players} ->
        result

      {%Player{} = player, players} ->
        effects = result.effects ++ remove_carried_aura(player, result.match) ++ player_left_effects(player)
        %{result | match: %{result.match | players: players}, effects: effects}
    end
  end

  def use_game_object(%__MODULE__{phase: :active} = match, guid, object_guid, entry, position, now) do
    with %Player{status: :inside} = player <- Map.get(match.players, guid),
         {:ok, flag_team, source} <- flag_source(match, object_guid, entry) do
      interact_with_flag(match, player, flag_team, source, object_guid, position, now)
    else
      _ -> {:unhandled, %Result{match: match}}
    end
  end

  def use_game_object(%__MODULE__{} = match, _guid, _object_guid, entry, _position, _now)
      when entry in [@alliance_flag_base, @horde_flag_base, @alliance_flag_ground, @horde_flag_ground] do
    {:handled, %Result{match: match}}
  end

  def use_game_object(%__MODULE__{} = match, _guid, _object_guid, _entry, _position, _now) do
    {:unhandled, %Result{match: match}}
  end

  def area_trigger(%__MODULE__{} = match, guid, trigger_id, _now)
      when trigger_id in [@alliance_exit_trigger, @horde_exit_trigger] do
    case Map.get(match.players, guid) do
      %Player{status: :inside, return_to: return_to} -> {:leave, return_to}
      _ -> :unhandled
    end
  end

  def area_trigger(%__MODULE__{phase: :active} = match, guid, trigger_id, now)
      when trigger_id in [@alliance_capture_trigger, @horde_capture_trigger] do
    case Map.get(match.players, guid) do
      %Player{status: :inside} = player -> capture_at(match, player, trigger_id, now)
      _ -> {:handled, %Result{match: match}}
    end
  end

  def area_trigger(%__MODULE__{}, _guid, _trigger_id, _now), do: :unhandled

  def player_died(%__MODULE__{} = match, victim_guid, killer_guid, position, dropped_guid) do
    match = update_death_scores(match, victim_guid, killer_guid)
    drop_carried_flag(match, victim_guid, position, dropped_guid)
  end

  def queue_resurrection(%__MODULE__{} = match, guid) do
    case Map.get(match.players, guid) do
      %Player{status: :inside} ->
        %Result{match: %{match | resurrection_queue: MapSet.put(match.resurrection_queue, guid)}}

      _ ->
        %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_one_minute, _now) do
    %Result{match: match, effects: [announce(10_015, :neutral)]}
  end

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start_half_minute, _now) do
    %Result{match: match, effects: [announce(10_016, :neutral)]}
  end

  def handle_timer(%__MODULE__{phase: :countdown} = match, :start, now) do
    match = %{match | phase: :active, started_at: now}

    %Result{
      match: match,
      effects: [
        %Effects.OperateGates{action: :open},
        %Effects.DespawnGhostGates{},
        announce(10_014, :neutral),
        %Effects.UpdateWorldStates{states: world_states(match)}
      ],
      timers: [status_refresh: 1_000]
    }
  end

  def handle_timer(%__MODULE__{phase: :active} = match, :status_refresh, _now) do
    %Result{
      match: match,
      effects: [
        %Effects.UpdateStatus{},
        %Effects.Scoreboard{ended?: false, players: scoreboard(match)}
      ]
    }
  end

  def handle_timer(%__MODULE__{} = match, {:flag_return, team, generation}, _now) do
    case Map.fetch!(match.flags, team) do
      %Flag{state: :ground, generation: ^generation, dropped_guid: guid} -> return_flag(match, team, guid, nil)
      _stale -> %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{} = match, {:flag_respawn, team, generation}, _now) do
    case Map.fetch!(match.flags, team) do
      %Flag{state: :waiting, generation: ^generation} -> respawn_captured_flags(match, team)
      _stale -> %Result{match: match}
    end
  end

  def handle_timer(%__MODULE__{phase: phase} = match, :resurrection_wave, now) when phase in [:countdown, :active] do
    guids = MapSet.to_list(match.resurrection_queue)
    effects = if guids == [], do: [], else: [%Effects.ResurrectPlayers{guids: guids}]

    %Result{
      match: %{match | resurrection_queue: MapSet.new(), next_resurrection_at: now + @resurrection_wave_ms},
      effects: effects,
      timers: [resurrection_timer(@resurrection_wave_ms)]
    }
  end

  def handle_timer(%__MODULE__{phase: {:ended, _winner}} = match, :auto_leave, _now) do
    destinations =
      match.players
      |> Map.values()
      |> Enum.filter(&(&1.status in [:inside, :offline] and not is_nil(&1.return_to)))
      |> Map.new(&{&1.guid, &1.return_to})

    %Result{match: match, effects: [%Effects.ExitPlayers{destinations: destinations}]}
  end

  def handle_timer(%__MODULE__{} = match, _key, _now), do: %Result{match: match}

  def world_states(%__MODULE__{} = match) do
    alliance = Map.fetch!(match.flags, :alliance)
    horde = Map.fetch!(match.flags, :horde)

    [
      {@world_state_captures_alliance, Map.fetch!(match.team_scores, :alliance)},
      {@world_state_captures_horde, Map.fetch!(match.team_scores, :horde)},
      {@world_state_flag_taken_alliance, taken_world_state(alliance)},
      {@world_state_flag_taken_horde, taken_world_state(horde)},
      {@world_state_captures_max, @max_score},
      {@world_state_flag_state_alliance, carrier_world_state(horde)},
      {@world_state_flag_state_horde, carrier_world_state(alliance)}
    ]
  end

  def scoreboard(%__MODULE__{} = match) do
    match.players
    |> Map.values()
    |> Enum.sort_by(& &1.guid)
    |> Enum.map(fn player ->
      %{
        guid: player.guid,
        rank: 4,
        killing_blows: player.killing_blows,
        honorable_kills: player.honorable_kills,
        deaths: player.deaths,
        bonus_honor: player.bonus_honor,
        fields: [player.flag_captures, player.flag_returns]
      }
    end)
  end

  def carried_flag(%__MODULE__{} = match, guid) do
    Enum.find_value(match.flags, fn
      {team, %Flag{state: :carried, carrier: ^guid}} -> team
      _flag -> nil
    end)
  end

  def active_player_guids(%__MODULE__{} = match) do
    match.players
    |> Map.values()
    |> Enum.filter(&(&1.status == :inside))
    |> Enum.map(& &1.guid)
  end

  def next_resurrection_ms(%__MODULE__{} = match, now) do
    case match.next_resurrection_at do
      at when is_integer(at) -> max(at - now, 0)
      _ -> @resurrection_wave_ms
    end
  end

  defp interact_with_flag(match, %Player{} = player, flag_team, :base, object_guid, _position, _now) do
    flag = Map.fetch!(match.flags, flag_team)

    if player.team != flag_team and flag.state == :base do
      {:handled, take_flag(match, player, flag_team, object_guid)}
    else
      {:handled, %Result{match: match}}
    end
  end

  defp interact_with_flag(match, %Player{} = player, flag_team, :ground, object_guid, _position, _now) do
    flag = Map.fetch!(match.flags, flag_team)

    cond do
      flag.state != :ground or flag.dropped_guid != object_guid ->
        {:handled, %Result{match: match}}

      player.team == flag_team ->
        {:handled, return_flag(match, flag_team, object_guid, player.guid)}

      true ->
        {:handled, retake_flag(match, player, flag_team, object_guid)}
    end
  end

  defp take_flag(match, player, flag_team, object_guid) do
    flag = Map.fetch!(match.flags, flag_team)
    flag = %{flag | state: :carried, carrier: player.guid, dropped_guid: nil, generation: flag.generation + 1}
    match = put_flag(match, flag_team, flag)

    %Result{
      match: match,
      effects: [
        %Effects.HideGameObject{guid: object_guid},
        %Effects.ApplyFlagAura{guid: player.guid, team: flag_team},
        announce(pickup_text(flag_team), player.team, player.guid),
        %Effects.PlaySound{sound_id: pickup_sound(flag_team)},
        %Effects.UpdateWorldStates{states: world_states(match)}
      ]
    }
  end

  defp retake_flag(match, player, flag_team, object_guid) do
    flag = Map.fetch!(match.flags, flag_team)
    flag = %{flag | state: :carried, carrier: player.guid, dropped_guid: nil, generation: flag.generation + 1}
    match = put_flag(match, flag_team, flag)

    %Result{
      match: match,
      effects: [
        %Effects.DespawnGameObject{guid: object_guid},
        %Effects.ApplyFlagAura{guid: player.guid, team: flag_team},
        announce(pickup_text(flag_team), player.team, player.guid),
        %Effects.PlaySound{sound_id: pickup_sound(flag_team)},
        %Effects.UpdateWorldStates{states: world_states(match)}
      ]
    }
  end

  defp return_flag(match, team, dropped_guid, actor_guid) do
    flag = Map.fetch!(match.flags, team)
    flag = %{flag | state: :base, carrier: nil, dropped_guid: nil, generation: flag.generation + 1}
    match = put_flag(match, team, flag)

    match =
      if is_integer(actor_guid),
        do: update_player(match, actor_guid, &%{&1 | flag_returns: &1.flag_returns + 1}),
        else: match

    announcement =
      if is_integer(actor_guid),
        do: announce(return_text(team), team, actor_guid),
        else: announce(respawn_text(team), :neutral)

    %Result{
      match: match,
      effects: [
        %Effects.DespawnGameObject{guid: dropped_guid},
        %Effects.ShowBaseFlag{team: team},
        announcement,
        %Effects.PlaySound{sound_id: @sound_flag_returned},
        %Effects.UpdateWorldStates{states: world_states(match)}
      ]
    }
  end

  defp capture_at(match, %Player{team: :alliance} = player, @alliance_capture_trigger, now) do
    capture_flag(match, player, :horde, :alliance, now)
  end

  defp capture_at(match, %Player{team: :horde} = player, @horde_capture_trigger, now) do
    capture_flag(match, player, :alliance, :horde, now)
  end

  defp capture_at(match, _player, _trigger_id, _now), do: {:handled, %Result{match: match}}

  defp capture_flag(match, player, captured_flag_team, scoring_team, now) do
    captured_flag = Map.fetch!(match.flags, captured_flag_team)
    own_flag = Map.fetch!(match.flags, scoring_team)

    if captured_flag.state == :carried and captured_flag.carrier == player.guid and own_flag.state == :base do
      generation = captured_flag.generation + 1
      captured_flag = %{captured_flag | state: :waiting, carrier: nil, dropped_guid: nil, generation: generation}
      match = put_flag(match, captured_flag_team, captured_flag)
      match = put_team_score(match, scoring_team, Map.fetch!(match.team_scores, scoring_team) + 1)
      match = update_player(match, player.guid, &%{&1 | flag_captures: &1.flag_captures + 1})
      match = reward_team_bonus(match, scoring_team, Enum.at(@flag_capture_honor, match.bracket, 0))

      effects = [
        %Effects.RemoveFlagAura{guid: player.guid, team: captured_flag_team},
        %Effects.HideBaseFlags{},
        announce(capture_text(captured_flag_team), scoring_team, player.guid),
        %Effects.RewardReputation{
          team: scoring_team,
          faction_id: reputation_faction(scoring_team),
          amount: 35
        },
        %Effects.PlaySound{sound_id: capture_sound(scoring_team)},
        %Effects.UpdateWorldStates{states: world_states(match)}
      ]

      if Map.fetch!(match.team_scores, scoring_team) >= @max_score do
        {:handled, end_match(match, scoring_team, now, effects)}
      else
        {:handled,
         %Result{
           match: match,
           effects: effects,
           timers: [{{:flag_respawn, captured_flag_team, generation}, @flag_respawn_ms}]
         }}
      end
    else
      {:handled, %Result{match: match}}
    end
  end

  defp respawn_captured_flags(match, _captured_team) do
    flags = Map.new(match.flags, fn {team, flag} -> {team, %{flag | state: :base, carrier: nil, dropped_guid: nil}} end)
    match = %{match | flags: flags}

    %Result{
      match: match,
      effects: [
        %Effects.ShowBaseFlag{team: :alliance},
        %Effects.ShowBaseFlag{team: :horde},
        announce(9_803, :neutral),
        %Effects.PlaySound{sound_id: @sound_flag_placed},
        %Effects.UpdateWorldStates{states: world_states(match)}
      ]
    }
  end

  defp drop_carried_flag(match, guid, position, dropped_guid) do
    case carried_flag(match, guid) do
      team when team in [:alliance, :horde] and is_integer(dropped_guid) and is_tuple(position) ->
        flag = Map.fetch!(match.flags, team)
        generation = flag.generation + 1
        flag = %{flag | state: :ground, carrier: nil, dropped_guid: dropped_guid, generation: generation}
        match = put_flag(match, team, flag)
        player = Map.get(match.players, guid)

        %Result{
          match: match,
          effects: [
            %Effects.RemoveFlagAura{guid: guid, team: team},
            %Effects.SpawnDroppedFlag{guid: dropped_guid, team: team, position: position},
            announce(drop_text(team), player_team(player), guid),
            %Effects.UpdateWorldStates{states: world_states(match)}
          ],
          timers: [{{:flag_return, team, generation}, @flag_drop_ms}]
        }

      _none ->
        %Result{match: match}
    end
  end

  defp end_match(match, winner, now, prior_effects) do
    match = reward_team_bonus(match, winner, Enum.at(@win_honor, match.bracket, 0))
    match = %{match | phase: {:ended, winner}, ended_at: now}
    aura_effects = carried_aura_effects(match)
    players = scoreboard(match)

    %Result{
      match: match,
      effects:
        prior_effects ++
          aura_effects ++
          [
            announce(win_text(winner), :neutral),
            %Effects.Scoreboard{ended?: true, winner: winner, players: players},
            %Effects.RewardPlayers{winner: winner, players: Map.values(match.players)}
          ],
      timers: [{:auto_leave, @auto_leave_ms}]
    }
  end

  defp update_death_scores(match, victim_guid, killer_guid) do
    match = update_player(match, victim_guid, &%{&1 | deaths: &1.deaths + 1})
    victim = Map.get(match.players, victim_guid)
    killer = Map.get(match.players, killer_guid)

    if is_struct(victim, Player) and is_struct(killer, Player) and victim.team != killer.team do
      update_player(match, killer_guid, fn player ->
        %{player | killing_blows: player.killing_blows + 1, honorable_kills: player.honorable_kills + 1}
      end)
    else
      match
    end
  end

  defp flag_source(match, _object_guid, @alliance_flag_base) do
    if Map.fetch!(match.flags, :alliance).state == :base, do: {:ok, :alliance, :base}, else: :error
  end

  defp flag_source(match, _object_guid, @horde_flag_base) do
    if Map.fetch!(match.flags, :horde).state == :base, do: {:ok, :horde, :base}, else: :error
  end

  defp flag_source(match, object_guid, @alliance_flag_ground) do
    flag = Map.fetch!(match.flags, :alliance)
    if flag.state == :ground and flag.dropped_guid == object_guid, do: {:ok, :alliance, :ground}, else: :error
  end

  defp flag_source(match, object_guid, @horde_flag_ground) do
    flag = Map.fetch!(match.flags, :horde)
    if flag.state == :ground and flag.dropped_guid == object_guid, do: {:ok, :horde, :ground}, else: :error
  end

  defp flag_source(_match, _object_guid, _entry), do: :error

  defp start_timers(delay) do
    [{:start, delay}]
    |> maybe_add_start_timer(:start_one_minute, delay - 60_000)
    |> maybe_add_start_timer(:start_half_minute, delay - 30_000)
  end

  defp maybe_add_start_timer(timers, _key, delay) when delay <= 0, do: timers
  defp maybe_add_start_timer(timers, key, delay), do: [{key, delay} | timers]

  defp resurrection_timer(delay), do: {:resurrection_wave, max(delay, 0)}

  defp taken_world_state(%Flag{state: :ground}), do: 0xFFFFFFFF
  defp taken_world_state(%Flag{state: :carried}), do: 1
  defp taken_world_state(%Flag{}), do: 0

  defp carrier_world_state(%Flag{state: :carried}), do: 2
  defp carrier_world_state(%Flag{}), do: 1

  defp put_player(match, %Player{} = player), do: %{match | players: Map.put(match.players, player.guid, player)}

  defp update_player(match, guid, update) do
    case Map.get(match.players, guid) do
      %Player{} = player -> put_player(match, update.(player))
      nil -> match
    end
  end

  defp put_flag(match, team, %Flag{} = flag), do: %{match | flags: Map.put(match.flags, team, flag)}
  defp put_team_score(match, team, score), do: %{match | team_scores: Map.put(match.team_scores, team, score)}

  defp reward_team_bonus(match, team, amount) do
    players =
      Map.new(match.players, fn {guid, player} ->
        player = if player.team == team, do: %{player | bonus_honor: player.bonus_honor + amount}, else: player
        {guid, player}
      end)

    %{match | players: players}
  end

  defp carried_aura_effects(match) do
    Enum.flat_map(match.flags, fn
      {team, %Flag{state: :carried, carrier: guid}} -> [%Effects.RemoveFlagAura{guid: guid, team: team}]
      _flag -> []
    end)
  end

  defp remove_carried_aura(%Player{guid: guid}, match) do
    case carried_flag(match, guid) do
      team when team in [:alliance, :horde] -> [%Effects.RemoveFlagAura{guid: guid, team: team}]
      _none -> []
    end
  end

  defp player_left_effects(%Player{status: status, guid: guid}) when status in [:inside, :offline],
    do: [%Effects.PlayerLeft{guid: guid}]

  defp player_left_effects(%Player{}), do: []

  defp announce(broadcast_text_id, audience, actor_guid \\ nil) do
    %Effects.Announce{broadcast_text_id: broadcast_text_id, audience: audience, actor_guid: actor_guid}
  end

  defp player_team(%Player{team: team}), do: team
  defp player_team(_player), do: :neutral

  defp pickup_text(:alliance), do: 9_804
  defp pickup_text(:horde), do: 9_807
  defp drop_text(:alliance), do: 9_805
  defp drop_text(:horde), do: 9_806
  defp return_text(:alliance), do: 9_808
  defp return_text(:horde), do: 9_809
  defp respawn_text(:alliance), do: 10_022
  defp respawn_text(:horde), do: 10_023
  defp capture_text(:alliance), do: 9_802
  defp capture_text(:horde), do: 9_801
  defp win_text(:alliance), do: 9_843
  defp win_text(:horde), do: 9_842
  defp pickup_sound(:alliance), do: @sound_alliance_flag_picked_up
  defp pickup_sound(:horde), do: @sound_horde_flag_picked_up
  defp capture_sound(:alliance), do: @sound_flag_captured_alliance
  defp capture_sound(:horde), do: @sound_flag_captured_horde
  defp reputation_faction(:alliance), do: 890
  defp reputation_faction(:horde), do: 889
end
