defmodule ThistleTea.Game.World.System.OutdoorPvp do
  @moduledoc "Serializes outdoor resource progress and tracks the live owners receiving zone updates."
  use GenServer

  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.OutdoorPvp.ResourceRace
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

  def world_states(zone, server \\ __MODULE__) do
    if Silithyst.objective_zone?(zone), do: states(snapshot(server)), else: []
  end

  @impl GenServer
  def init(opts), do: {:ok, %{race: Keyword.get(opts, :race, %ResourceRace{}), members: %{}}}

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

  defp handle_request(:snapshot, _from, state), do: {:reply, state.race, state}

  defp handle_request({:sync, guid, world, zone, team}, {pid, _tag}, state) do
    state = update_member(state, guid, pid, world, zone, team)
    enabled? = Silithyst.buff_zone?(zone) and state.race.controller == team and not is_nil(team)
    states = if Silithyst.objective_zone?(zone), do: states(state.race), else: cleared_states()
    {:reply, %{states: states, favor?: enabled?}, state}
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
    if Silithyst.buff_zone?(zone) do
      member =
        case state.members[guid] do
          %{pid: ^pid} = existing -> %{existing | world: world, zone: zone, team: team}
          _ -> %{pid: pid, world: world, zone: zone, team: team, monitor: Process.monitor(pid), last_token: nil}
        end

      state = if match?(%{pid: ^pid}, state.members[guid]), do: state, else: remove_member(state, guid)
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
end
