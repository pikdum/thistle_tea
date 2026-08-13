defmodule ThistleTea.Game.World.System.Battleground do
  @moduledoc """
  Owns battleground queues, invitations, match admission, and player indexes.
  """
  use GenServer

  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Battleground.EffectSink
  alias ThistleTea.Game.World.Battleground.Match
  alias ThistleTea.Game.World.Battleground.Supervisor, as: MatchSupervisor
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.WorldRef

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def join(player, map_id, server \\ __MODULE__) when is_map(player) and is_integer(map_id) do
    join_group([player], map_id, server)
  end

  def join_group(players, map_id, server \\ __MODULE__) when is_list(players) and is_integer(map_id) do
    join_group_for_instance(players, map_id, 0, server)
  end

  def join_group_for_instance(players, map_id, client_instance_id, server \\ __MODULE__)
      when is_list(players) and is_integer(map_id) and is_integer(client_instance_id) do
    GenServer.call(server, {:join_group, players, map_id, client_instance_id})
  end

  def leave_queue(guid, server \\ __MODULE__) when is_integer(guid), do: GenServer.call(server, {:leave_queue, guid})
  def list(map_id, level, server \\ __MODULE__), do: GenServer.call(server, {:list, map_id, level})
  def status(guid, server \\ __MODULE__) when is_integer(guid), do: GenServer.call(server, {:status, guid})
  def debug_info(guid, server \\ __MODULE__) when is_integer(guid), do: GenServer.call(server, {:debug_info, guid})

  def debug_start_queued(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:debug_start_queued, guid})
  end

  def debug_start_now(%WorldRef{} = world, server \\ __MODULE__) do
    GenServer.call(server, {:debug_start_now, world})
  end

  def port(guid, action, return_to, server \\ __MODULE__) when action in [0, 1] do
    GenServer.call(server, {:port, guid, action, return_to})
  end

  def leave(guid, position, server \\ __MODULE__) do
    GenServer.call(server, {:leave, guid, position})
  end

  def use_game_object(%WorldRef{} = world, guid, object_guid, entry, position, server \\ __MODULE__) do
    GenServer.call(server, {:use_game_object, world, guid, object_guid, entry, position})
  end

  def area_trigger(%WorldRef{} = world, guid, trigger_id, position, server \\ __MODULE__) do
    GenServer.call(server, {:area_trigger, world, guid, trigger_id, position})
  end

  def player_died(%WorldRef{} = world, victim_guid, killer_guid, position, server \\ __MODULE__) do
    GenServer.cast(server, {:player_died, world, victim_guid, killer_guid, position})
  end

  def queue_resurrection(%WorldRef{} = world, guid, server \\ __MODULE__) do
    GenServer.cast(server, {:queue_resurrection, world, guid})
  end

  def spirit_healer_time(%WorldRef{} = world, server \\ __MODULE__) do
    GenServer.call(server, {:spirit_healer_time, world})
  end

  def scoreboard(%WorldRef{} = world, server \\ __MODULE__), do: GenServer.call(server, {:scoreboard, world})
  def world_states(%WorldRef{} = world, server \\ __MODULE__), do: GenServer.call(server, {:world_states, world})
  def graveyard(%WorldRef{} = world, guid, server \\ __MODULE__), do: GenServer.call(server, {:graveyard, world, guid})
  def match_for_world(%WorldRef{} = world, server \\ __MODULE__), do: GenServer.call(server, {:match_for_world, world})

  def reconnect(guid, %WorldRef{} = world, server \\ __MODULE__) do
    GenServer.call(server, {:reconnect, guid, world})
  end

  def game_object_spawned(%WorldRef{} = world, guid, entry, server \\ __MODULE__) do
    GenServer.cast(server, {:game_object_spawned, world, guid, entry})
  end

  def disconnect(guid, position, server \\ __MODULE__) do
    GenServer.cast(server, {:disconnect, guid, position})
  end

  def world_left(guid, %WorldRef{} = world, position, server \\ __MODULE__) do
    GenServer.cast(server, {:world_left, guid, world, position})
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       queues: %{},
       players: %{},
       matches: %{},
       worlds: %{},
       next_instance_id: Keyword.get(opts, :next_instance_id, 1),
       catalog: Keyword.get(opts, :catalog, BattlegroundLoader),
       match_supervisor: Keyword.get(opts, :match_supervisor, MatchSupervisor),
       match_options: Keyword.get(opts, :match_options, []),
       effect_sink: Keyword.get(opts, :effect_sink, &EffectSink.emit/2)
     }}
  end

  @impl GenServer
  def handle_call({:join_group, players, map_id, desired_instance_id}, _from, state) do
    case validate_group(state, players, map_id) do
      {:ok, template, bracket, team} ->
        reservations = Enum.map(players, &Map.take(&1, [:guid, :name, :team]))

        case joinable_match(state, map_id, bracket, team, length(players), desired_instance_id) do
          {:ok, pid} ->
            :ok = Match.reserve(pid, reservations)
            {:reply, :ok, invite_players(state, pid, reservations)}

          :not_found when desired_instance_id > 0 ->
            {:reply, {:error, :invalid_instance}, state}

          :not_found ->
            state = enqueue(state, map_id, bracket, team, reservations)
            {:reply, :ok, maybe_start_matches(state, map_id, bracket, template)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave_queue, guid}, _from, state) do
    {:reply, :ok, remove_player(state, guid, nil)}
  end

  def handle_call({:list, map_id, level}, _from, state) do
    template = state.catalog.template_for_map(map_id)
    bracket = Battleground.bracket(level)

    instances =
      state.matches
      |> Enum.flat_map(fn {pid, info} ->
        if info.world.map_id == map_id and info.bracket == bracket and joinable_for_either_team?(pid, info) do
          [info.client_instance_id]
        else
          []
        end
      end)
      |> Enum.sort()

    {:reply, %{template: template, bracket: bracket, instances: instances}, state}
  end

  def handle_call({:status, guid}, _from, state) do
    {:reply, status_for(state, guid), state}
  end

  def handle_call({:debug_info, guid}, _from, state) do
    {:reply, debug_info_for(state, guid), state}
  end

  def handle_call({:debug_start_queued, guid}, _from, state) do
    case Map.get(state.players, guid) do
      {:queued, {map_id, bracket, _team} = key, _joined_at} ->
        with {:ok, reservation, queue} <- pop_reservation(Map.get(state.queues, key, []), guid),
             template when not is_nil(template) <- state.catalog.template_for_map(map_id) do
          state = %{state | queues: Map.put(state.queues, key, queue)}
          state = start_match(state, map_id, bracket, template, [reservation])
          {:reply, {:ok, status_for(state, guid)}, state}
        else
          _missing -> {:reply, {:error, :queue_inconsistent}, state}
        end

      {:invited, _pid, _team} ->
        {:reply, {:error, :already_invited}, state}

      {:inside, _pid, _team} ->
        {:reply, {:error, :already_inside}, state}

      nil ->
        {:reply, {:error, :not_queued}, state}
    end
  end

  def handle_call({:debug_start_now, world}, _from, state) do
    case Map.get(state.worlds, world) do
      pid when is_pid(pid) -> {:reply, Match.start_now(pid), state}
      nil -> {:reply, {:error, :not_in_battleground}, state}
    end
  end

  def handle_call({:port, guid, 0, _return_to}, _from, state) do
    state =
      case Map.get(state.players, guid) do
        {:invited, pid, _team} ->
          :ok = Match.leave(pid, guid, nil, dropped_flag_guid())
          remove_player(state, guid, pid)

        _status ->
          remove_player(state, guid, nil)
      end

    {:reply, :ok, state}
  end

  def handle_call({:port, guid, 1, return_to}, _from, state) do
    case Map.get(state.players, guid) do
      {:invited, pid, team} ->
        case Match.enter(pid, guid, return_to) do
          nil ->
            {:reply, {:error, :invitation_expired}, remove_player(state, guid, nil)}

          _player ->
            info = Map.fetch!(state.matches, pid)
            destination = team_destination(info.template, team)
            state = %{state | players: Map.put(state.players, guid, {:inside, pid, team})}
            {:reply, {:ok, info.world, destination}, state}
        end

      {:inside, pid, team} ->
        info = Map.fetch!(state.matches, pid)
        {:reply, {:ok, info.world, team_destination(info.template, team)}, state}

      _ ->
        {:reply, {:error, :not_invited}, state}
    end
  end

  def handle_call({:leave, guid, position}, _from, state) do
    case Map.get(state.players, guid) do
      {:inside, pid, _team} ->
        return_to = return_destination(pid, guid)
        :ok = Match.leave(pid, guid, position, dropped_flag_guid())
        {:reply, {:ok, return_to}, remove_player(state, guid, pid)}

      _ ->
        {:reply, {:error, :not_inside}, state}
    end
  end

  def handle_call({:use_game_object, world, guid, object_guid, entry, position}, _from, state) do
    reply =
      with pid when is_pid(pid) <- Map.get(state.worlds, world),
           do: Match.use_game_object(pid, guid, object_guid, entry, position)

    {:reply, reply || :unhandled, state}
  end

  def handle_call({:area_trigger, world, guid, trigger_id, position}, _from, state) do
    reply =
      with pid when is_pid(pid) <- Map.get(state.worlds, world),
           do: Match.area_trigger(pid, guid, trigger_id, position, dropped_flag_guid())

    {:reply, reply || :unhandled, state}
  end

  def handle_call({:spirit_healer_time, world}, _from, state) do
    reply = with pid when is_pid(pid) <- Map.get(state.worlds, world), do: Match.spirit_healer_time(pid)
    {:reply, reply, state}
  end

  def handle_call({:scoreboard, world}, _from, state) do
    reply = with pid when is_pid(pid) <- Map.get(state.worlds, world), do: Match.scoreboard(pid)
    {:reply, reply || [], state}
  end

  def handle_call({:world_states, world}, _from, state) do
    reply = with pid when is_pid(pid) <- Map.get(state.worlds, world), do: Match.world_states(pid)
    {:reply, reply || [], state}
  end

  def handle_call({:graveyard, world, guid}, _from, state) do
    reply =
      with pid when is_pid(pid) <- Map.get(state.worlds, world),
           match = Match.snapshot(pid),
           %{team: team} <- Map.get(match.players, guid) do
        team_graveyard(match.template, team)
      else
        _missing -> nil
      end

    {:reply, reply, state}
  end

  def handle_call({:match_for_world, world}, _from, state), do: {:reply, Map.get(state.worlds, world), state}

  def handle_call({:reconnect, guid, world}, _from, state) do
    case {Map.get(state.worlds, world), Map.get(state.players, guid)} do
      {pid, {:invited, pid, team}} when is_pid(pid) ->
        Match.reconnect(pid, guid)
        {:reply, :ok, %{state | players: Map.put(state.players, guid, {:inside, pid, team})}}

      {pid, {:inside, pid, _team}} when is_pid(pid) ->
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :not_reserved}, state}
    end
  end

  @impl GenServer
  def handle_cast({:player_died, world, victim_guid, killer_guid, position}, state) do
    if pid = Map.get(state.worlds, world) do
      Match.player_died(pid, victim_guid, killer_guid, position, dropped_flag_guid())
    end

    {:noreply, state}
  end

  def handle_cast({:queue_resurrection, world, guid}, state) do
    if pid = Map.get(state.worlds, world), do: Match.queue_resurrection(pid, guid)
    {:noreply, state}
  end

  def handle_cast({:disconnect, guid, position}, state) do
    case Map.get(state.players, guid) do
      {:inside, pid, team} ->
        Match.disconnect(pid, guid, position, dropped_flag_guid())
        {:noreply, %{state | players: Map.put(state.players, guid, {:invited, pid, team})}}

      _ ->
        {:noreply, remove_player(state, guid, nil)}
    end
  end

  def handle_cast({:game_object_spawned, world, guid, entry}, state) do
    case Map.get(state.worlds, world) do
      pid when is_pid(pid) -> reconcile_game_object(pid, guid, entry, state.catalog)
      _missing -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:world_left, guid, world, position}, state) do
    case {Map.get(state.worlds, world), Map.get(state.players, guid)} do
      {pid, {:inside, pid, _team}} when is_pid(pid) ->
        Match.leave(pid, guid, position, dropped_flag_guid())
        {:noreply, remove_player(state, guid, pid)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:match_player_left, pid, guid}, state) do
    {:noreply, remove_player(state, guid, pid)}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.matches, pid) do
      %{monitor: ^ref, world: world} ->
        players = Map.reject(state.players, fn {_guid, status} -> match_pid(status) == pid end)

        {:noreply,
         %{state | players: players, matches: Map.delete(state.matches, pid), worlds: Map.delete(state.worlds, world)}}

      _ ->
        {:noreply, state}
    end
  end

  defp maybe_start_matches(state, map_id, bracket, template) do
    alliance_key = {map_id, bracket, :alliance}
    horde_key = {map_id, bracket, :horde}
    alliance = Map.get(state.queues, alliance_key, [])
    horde = Map.get(state.queues, horde_key, [])
    minimum = template.min_players_per_team

    if length(alliance) >= minimum and length(horde) >= minimum do
      maximum = template.max_players_per_team
      {alliance_players, alliance_queue} = Enum.split(alliance, maximum)
      {horde_players, horde_queue} = Enum.split(horde, maximum)

      state = %{
        state
        | queues: state.queues |> Map.put(alliance_key, alliance_queue) |> Map.put(horde_key, horde_queue)
      }

      state
      |> start_match(map_id, bracket, template, alliance_players ++ horde_players)
      |> maybe_start_matches(map_id, bracket, template)
    else
      state
    end
  end

  defp validate_group(state, players, map_id) do
    case state.catalog.template_for_map(map_id) do
      nil -> {:error, :unsupported_battleground}
      template -> validate_roster(state, players, template)
    end
  end

  defp validate_roster(state, players, template) do
    cond do
      players == [] -> {:error, :empty_group}
      length(Enum.uniq_by(players, & &1.guid)) != length(players) -> {:error, :duplicate_member}
      Enum.any?(players, &(not is_nil(Map.get(state.players, &1.guid)))) -> {:error, :already_queued}
      true -> validate_eligibility(players, template)
    end
  end

  defp validate_eligibility(players, template) do
    teams = Enum.map(players, & &1.team) |> Enum.uniq()
    brackets = Enum.map(players, &Battleground.bracket(&1.level)) |> Enum.uniq()

    cond do
      Enum.any?(players, &(&1.level < template.min_level or &1.level > template.max_level)) ->
        {:error, :level_restricted}

      teams not in [[:alliance], [:horde]] ->
        {:error, :invalid_team}

      length(brackets) != 1 ->
        {:error, :mixed_bracket}

      length(players) > template.max_players_per_team ->
        {:error, :group_too_large}

      true ->
        {:ok, template, hd(brackets), hd(teams)}
    end
  end

  defp enqueue(state, map_id, bracket, team, reservations) do
    key = {map_id, bracket, team}
    queue = Map.get(state.queues, key, []) ++ reservations
    joined_at = Time.now()

    players =
      Enum.reduce(reservations, state.players, fn player, index ->
        Map.put(index, player.guid, {:queued, key, joined_at})
      end)

    %{state | queues: Map.put(state.queues, key, queue), players: players}
  end

  defp pop_reservation(queue, guid) do
    case Enum.split_while(queue, &(&1.guid != guid)) do
      {before, [reservation | after_reservation]} -> {:ok, reservation, before ++ after_reservation}
      {_before, []} -> :error
    end
  end

  defp joinable_match(state, map_id, bracket, team, group_size, desired_instance_id) do
    state.matches
    |> Enum.sort_by(fn {_pid, info} -> info.client_instance_id end)
    |> Enum.find_value(:not_found, fn {pid, info} ->
      match = Match.snapshot(pid)
      team_count = Enum.count(match.players, fn {_guid, player} -> player.team == team end)
      desired? = desired_instance_id == 0 or info.client_instance_id == desired_instance_id

      if info.world.map_id == map_id and info.bracket == bracket and desired? and
           match.phase in [:countdown, :active] and
           team_count + group_size <= info.template.max_players_per_team do
        {:ok, pid}
      end
    end)
  end

  defp invite_players(state, pid, reservations) do
    players =
      Enum.reduce(reservations, state.players, fn player, index ->
        Map.put(index, player.guid, {:invited, pid, player.team})
      end)

    %{state | players: players}
  end

  defp joinable_for_either_team?(pid, info) do
    match = Match.snapshot(pid)
    maximum = info.template.max_players_per_team
    alliance = Enum.count(match.players, fn {_guid, player} -> player.team == :alliance end)
    horde = Enum.count(match.players, fn {_guid, player} -> player.team == :horde end)
    match.phase in [:countdown, :active] and (alliance < maximum or horde < maximum)
  end

  defp start_match(state, map_id, bracket, template, reservations) do
    instance_id = state.next_instance_id
    world = WorldRef.instance(map_id, instance_id)

    opts = [
      world: world,
      client_instance_id: instance_id,
      bracket: bracket,
      template: template,
      reservations: reservations,
      manager: self(),
      match_options: state.match_options,
      effect_sink: state.effect_sink
    ]

    {:ok, pid} = MatchSupervisor.start_match(opts, state.match_supervisor)
    monitor = Process.monitor(pid)
    info = %{world: world, client_instance_id: instance_id, bracket: bracket, template: template, monitor: monitor}

    players =
      Enum.reduce(reservations, state.players, fn player, players ->
        Map.put(players, player.guid, {:invited, pid, player.team})
      end)

    %{
      state
      | players: players,
        matches: Map.put(state.matches, pid, info),
        worlds: Map.put(state.worlds, world, pid),
        next_instance_id: instance_id + 1
    }
  end

  defp remove_player(state, guid, expected_pid) do
    case Map.get(state.players, guid) do
      {:queued, key, _at} ->
        queue = Map.get(state.queues, key, []) |> Enum.reject(&(&1.guid == guid))
        %{state | queues: Map.put(state.queues, key, queue), players: Map.delete(state.players, guid)}

      status ->
        if is_nil(expected_pid) or match_pid(status) == expected_pid do
          %{state | players: Map.delete(state.players, guid)}
        else
          state
        end
    end
  end

  defp status_for(state, guid) do
    case Map.get(state.players, guid) do
      {:queued, {map_id, bracket, _team}, joined_at} ->
        %{status: :wait_queue, map_id: map_id, bracket: bracket, elapsed_ms: Time.now() - joined_at}

      {:invited, pid, _team} ->
        info = Map.fetch!(state.matches, pid)

        %{
          status: :wait_join,
          map_id: info.world.map_id,
          bracket: info.bracket,
          client_instance_id: info.client_instance_id
        }

      {:inside, pid, _team} ->
        info = Map.fetch!(state.matches, pid)
        match = Match.snapshot(pid)

        auto_leave_ms =
          case match.ended_at do
            ended_at when is_integer(ended_at) -> max(ended_at + 120_000 - Time.now(), 0)
            _active -> 0
          end

        %{
          status: :in_progress,
          map_id: info.world.map_id,
          bracket: info.bracket,
          client_instance_id: info.client_instance_id,
          started_at: match.started_at,
          auto_leave_ms: auto_leave_ms
        }

      nil ->
        %{status: :none}
    end
  end

  defp debug_info_for(state, guid) do
    status = status_for(state, guid)

    case Map.get(state.players, guid) do
      {status_kind, pid, _team} when status_kind in [:invited, :inside] ->
        info = Map.fetch!(state.matches, pid)
        match = Match.snapshot(pid)
        team_counts = match.players |> Map.values() |> Enum.frequencies_by(& &1.team)

        Map.merge(status, %{
          world: info.world,
          phase: match.phase,
          scores: match.team_scores,
          flags: Map.new(match.flags, fn {team, flag} -> {team, flag.state} end),
          players: %{
            alliance: Map.get(team_counts, :alliance, 0),
            horde: Map.get(team_counts, :horde, 0),
            inside: Enum.count(match.players, fn {_player_guid, player} -> player.status == :inside end)
          }
        })

      _status ->
        status
    end
  end

  defp return_destination(pid, guid) do
    pid
    |> Match.snapshot()
    |> Map.fetch!(:players)
    |> Map.get(guid)
    |> then(fn
      nil -> nil
      player -> player.return_to
    end)
  end

  defp team_destination(template, :alliance), do: template.alliance_start
  defp team_destination(template, :horde), do: template.horde_start
  defp team_graveyard(template, :alliance), do: template.alliance_graveyard || template.alliance_start
  defp team_graveyard(template, :horde), do: template.horde_graveyard || template.horde_start

  defp match_pid({:invited, pid, _team}), do: pid
  defp match_pid({:inside, pid, _team}), do: pid
  defp match_pid(_status), do: nil

  defp dropped_flag_guid do
    :erlang.unique_integer([:positive, :monotonic])
  end

  defp reconcile_game_object(pid, guid, entry, catalog) do
    match = Match.snapshot(pid)

    cond do
      entry in catalog.gate_entries() ->
        action = if match.phase == :countdown, do: :close, else: :open
        Entity.operate_game_object(guid, action)

      entry == 179_830 and match.flags.alliance.state != :base ->
        Entity.hide_game_object(guid)

      entry == 179_831 and match.flags.horde.state != :base ->
        Entity.hide_game_object(guid)

      true ->
        :ok
    end
  end
end
