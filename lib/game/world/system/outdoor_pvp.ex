defmodule ThistleTea.Game.World.System.OutdoorPvp do
  @moduledoc "Owns outdoor resource races, capture-point progress, and monitored regional subscriptions."
  use GenServer

  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.OutdoorPvp.ResourceRace
  alias ThistleTea.Game.OutdoorPvp.Towers
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.OutdoorPvp.CaptureAnnouncements
  alias ThistleTea.Game.World.OutdoorPvp.CaptureEnvironment
  alias ThistleTea.Game.World.OutdoorPvp.CaptureRewards
  alias ThistleTea.Game.WorldRef

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def sync(guid, world, zone, team, server \\ __MODULE__), do: GenServer.call(server, {:sync, guid, world, zone, team})

  def contribute(guid, world, team, token, server \\ __MODULE__),
    do: GenServer.call(server, {:contribute, guid, world, team, token})

  def leave(guid, server \\ __MODULE__), do: GenServer.call(server, {:leave, guid})
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)
  def tower_snapshot(server \\ __MODULE__), do: GenServer.call(server, :tower_snapshot)

  def configure_towers(towers, objects, server \\ __MODULE__),
    do: GenServer.call(server, {:configure_towers, towers, objects})

  def advance(now, server \\ __MODULE__), do: GenServer.call(server, {:advance, now})

  def world_states(zone, server \\ __MODULE__) do
    GenServer.call(server, {:world_states, zone})
  end

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, &Time.now/0)

    {:ok,
     %{
       race: Keyword.get(opts, :race, %ResourceRace{}),
       members: %{},
       towers: Keyword.get(opts, :towers, %Towers{}),
       objects: %{},
       rewards: %{},
       rewards_enabled?: false,
       timer: nil,
       interval_ms: Keyword.get(opts, :interval_ms, 1000),
       updated_at: clock.(),
       clock: clock,
       participants: Keyword.get(opts, :participants, &CaptureEnvironment.participants/1)
     }}
  end

  @impl GenServer
  def handle_call(request, from, state) do
    handle_request(request, from, state)
  rescue
    error ->
      Logger.error("Outdoor PvP request failed: #{Exception.message(error)}")
      {:reply, {:error, :unavailable}, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    members = Map.reject(state.members, fn {_guid, member} -> member.monitor == ref end)
    {:noreply, %{state | members: members}}
  rescue
    error ->
      Logger.error("Outdoor PvP owner cleanup failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_info({:timeout, timer, :capture_points}, %{timer: timer} = state) do
    state = %{state | timer: nil}
    {:noreply, state |> advance_towers(state.clock.()) |> schedule_tick()}
  rescue
    error ->
      Logger.error("Outdoor capture update failed: #{Exception.message(error)}")
      {:noreply, schedule_tick(%{state | timer: nil})}
  end

  def handle_info({:timeout, _stale, :capture_points}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    CaptureEnvironment.stop_banners(state.objects)
    CaptureRewards.stop(state.rewards)
  end

  defp handle_request(:snapshot, _from, state), do: {:reply, state.race, state}
  defp handle_request(:tower_snapshot, _from, state), do: {:reply, state.towers, state}

  defp handle_request({:world_states, zone}, _from, state) do
    states =
      cond do
        Silithyst.objective_zone?(zone) -> states(state.race)
        Plaguelands.objective_zone?(zone) -> Towers.world_states(state.towers) ++ [{2426, 0}, {2428, 20}, {2427, 50}]
        true -> []
      end

    {:reply, states, state}
  end

  defp handle_request({:configure_towers, %Towers{} = towers, objects}, _from, state) do
    CaptureEnvironment.stop_banners(state.objects)
    rewards = CaptureRewards.reconcile(state.rewards, towers)

    state = %{
      state
      | towers: towers,
        objects: objects,
        rewards: rewards,
        rewards_enabled?: true,
        updated_at: state.clock.()
    }

    {:reply, :ok, schedule_tick(state)}
  end

  defp handle_request({:advance, now}, _from, state) do
    state = advance_towers(state, now)
    {:reply, state.towers, state}
  end

  defp handle_request({:sync, guid, world, zone, team}, {pid, _tag}, state) do
    state = update_member(state, guid, pid, world, zone, team)
    enabled? = Silithyst.buff_zone?(zone) and state.race.controller == team and not is_nil(team)
    states = if Silithyst.objective_zone?(zone), do: states(state.race), else: cleared_states()

    tower_states =
      if Plaguelands.objective_zone?(zone),
        do: Towers.world_states(state.towers) ++ Towers.slider_states(state.towers, guid),
        else: Enum.map(Towers.world_states(state.towers), fn {field, _value} -> {field, 0} end) ++ [{2426, 0}]

    buff = if Plaguelands.buff_zone?(zone), do: Towers.buff(state.towers, team)

    token =
      case state.members[guid] do
        %{token: token} -> token
        nil -> nil
      end

    {:reply, %{states: states ++ tower_states, favor?: enabled?, tower_buff: buff, token: token}, state}
  end

  defp handle_request({:leave, guid}, {pid, _tag}, state) do
    state = if match?(%{pid: ^pid}, state.members[guid]), do: remove_member(state, guid), else: state
    {:reply, :ok, state}
  end

  defp handle_request({:contribute, guid, %WorldRef{map_id: 1, instance_id: nil} = world, team, token}, {pid, _}, state)
       when team in [:alliance, :horde] do
    case state.members[guid] do
      %{pid: ^pid, world: ^world, zone: 1377, team: ^team, last_token: previous} = member when previous != token ->
        {race, outcome} = ResourceRace.contribute(state.race, team)
        members = Map.put(state.members, guid, %{member | last_token: token})
        state = %{state | race: race, members: members}
        Enum.each(members, fn {_guid, member} -> send(member.pid, :refresh_outdoor_pvp) end)
        {:reply, {:ok, outcome}, state}

      _ ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  defp handle_request({:contribute, _guid, _world, _team, _token}, _from, state),
    do: {:reply, {:error, :unavailable}, state}

  defp update_member(state, guid, pid, world, zone, team) do
    if Silithyst.buff_zone?(zone) or Plaguelands.buff_zone?(zone) do
      member =
        case state.members[guid] do
          %{pid: ^pid, world: ^world, zone: ^zone, team: ^team} = existing ->
            existing

          _ ->
            %{
              pid: pid,
              world: world,
              zone: zone,
              team: team,
              monitor: Process.monitor(pid),
              last_token: nil,
              token: make_ref()
            }
        end

      state = if state.members[guid] == member, do: state, else: remove_member(state, guid)
      %{state | members: Map.put(state.members, guid, member)}
    else
      remove_member(state, guid)
    end
  end

  defp remove_member(state, guid) do
    case Map.pop(state.members, guid) do
      {nil, _members} ->
        state

      {%{monitor: ref}, members} ->
        Process.demonitor(ref, [:flush])
        %{state | members: members}
    end
  end

  defp states(%ResourceRace{} = race), do: [{2313, race.alliance}, {2314, race.horde}, {2317, race.limit}]
  defp cleared_states, do: [{2313, 0}, {2314, 0}, {2317, 0}]

  defp schedule_tick(%{timer: nil, interval_ms: interval} = state) when is_integer(interval) and interval > 0,
    do: %{state | timer: :erlang.start_timer(interval, self(), :capture_points)}

  defp schedule_tick(state), do: state

  defp advance_towers(state, now) do
    previous = state.towers
    participants = state.participants.(state.members)
    current = Towers.advance(previous, participants, max(now - state.updated_at, 0))

    Enum.each(Towers.ownership_changes(previous, current), fn {id, _before, owner} ->
      CaptureEnvironment.update_banners(state.objects, id, owner)
      reward_capture(state.members, participants, id, owner)
    end)

    CaptureAnnouncements.publish(previous, current)

    rewards = if state.rewards_enabled?, do: CaptureRewards.reconcile(state.rewards, current), else: state.rewards

    Enum.each(state.members, &project_towers(&1, previous, current))

    %{state | towers: current, rewards: rewards, updated_at: now}
  end

  defp project_towers({guid, member}, previous, current) do
    if Plaguelands.buff_zone?(member.zone) do
      states = if Plaguelands.objective_zone?(member.zone), do: Towers.updates(previous, current, guid), else: []
      buff = Towers.buff(current, member.team)

      if states != [] or buff != Towers.buff(previous, member.team),
        do: send(member.pid, {:outdoor_pvp_update, member.token, states, buff})
    end
  end

  defp reward_capture(members, participants, id, owner) do
    participants
    |> Towers.capture_recipients(id, owner)
    |> Enum.uniq()
    |> Enum.each(fn guid ->
      case members[guid] do
        %{pid: pid, token: token} -> send(pid, {:outdoor_pvp_credit, token, Plaguelands.towers()[id].credit_entry})
        _missing -> :ok
      end
    end)
  end
end
