defmodule ThistleTea.Game.World.System.Weather do
  @moduledoc "Owns shared weather per world and zone, with monitored player subscriptions and independent roll timers."
  use GenServer

  alias ThistleTea.Game.Time
  alias ThistleTea.Game.Weather
  alias ThistleTea.Game.World.Loader.Weather, as: WeatherLoader
  alias ThistleTea.Game.WorldRef

  require Logger

  defmodule Zone do
    @moduledoc false
    defstruct [:timer, :token, :next_roll_at, weather: %Weather{}, permanent?: false]
  end

  defmodule Member do
    @moduledoc false
    defstruct [:pid, :monitor, :key, :token]
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def sync(guid, %WorldRef{} = world, zone, server \\ __MODULE__),
    do: GenServer.call(server, {:sync, guid, {world, zone}})

  def leave(guid, server \\ __MODULE__), do: GenServer.call(server, {:leave, guid})
  def clear_world(world, server \\ __MODULE__), do: GenServer.call(server, {:clear_world, world})
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  def set(world, zone, type, grade, permanent? \\ false, server \\ __MODULE__) do
    with {:ok, weather} <- Weather.set(type, grade) do
      GenServer.call(server, {:set, {world, zone}, weather, permanent?})
    end
  end

  def resume(world, zone, server \\ __MODULE__), do: GenServer.call(server, {:resume, {world, zone}})
  def advance(world, zone, server \\ __MODULE__), do: GenServer.call(server, {:advance, {world, zone}})

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       zones: %{},
       members: %{},
       interval_ms: Keyword.get(opts, :interval_ms, 600_000),
       lookup: Keyword.get(opts, :lookup, &WeatherLoader.get/2),
       date: Keyword.get(opts, :date, &Date.utc_today/0),
       sample: Keyword.get(opts, :sample, &sample/0)
     }}
  end

  @impl GenServer
  def handle_call(request, from, state) do
    handle_request(request, from, state)
  rescue
    error ->
      Logger.error("Weather request failed: #{Exception.message(error)}")
      {:reply, {:error, :unavailable}, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    handle_message(message, state)
  rescue
    error ->
      Logger.error("Weather update failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state), do: Enum.each(state.zones, fn {_key, zone} -> Process.cancel_timer(zone.timer) end)

  defp handle_request(:snapshot, _from, state), do: {:reply, Map.take(state, [:zones, :members]), state}

  defp handle_request({:sync, guid, key}, {pid, _tag}, state) do
    state = state |> remove_member(guid) |> ensure_zone(key)
    member = %Member{pid: pid, monitor: Process.monitor(pid), key: key, token: make_ref()}
    state = %{state | members: Map.put(state.members, guid, member)}
    {:reply, {member.token, state.zones[key].weather}, state}
  end

  defp handle_request({:leave, guid}, {pid, _tag}, state) do
    state = if match?(%Member{pid: ^pid}, state.members[guid]), do: remove_member(state, guid), else: state
    {:reply, :ok, state}
  end

  defp handle_request({:clear_world, world}, _from, state) do
    state =
      Enum.reduce(state.zones, state, fn
        {{^world, _zone} = key, _value}, state -> remove_zone(state, key)
        _entry, state -> state
      end)

    state =
      Enum.reduce(state.members, state, fn
        {guid, %Member{key: {^world, _zone}}}, state -> remove_member(state, guid)
        _entry, state -> state
      end)

    {:reply, :ok, state}
  end

  defp handle_request({:set, key, weather, permanent?}, _from, state) do
    state = ensure_zone(state, key)
    zone = %{state.zones[key] | weather: weather, permanent?: permanent?}
    state = %{state | zones: Map.put(state.zones, key, zone)}
    broadcast(state, key, weather)
    {:reply, weather, state}
  end

  defp handle_request({:resume, key}, _from, state) do
    state = ensure_zone(state, key)
    zone = %{state.zones[key] | permanent?: false}
    {:reply, zone.weather, %{state | zones: Map.put(state.zones, key, zone)}}
  end

  defp handle_request({:advance, key}, _from, state) do
    state = state |> ensure_zone(key) |> advance_zone(key)
    {:reply, state.zones[key].weather, state}
  end

  defp handle_message({:roll, key, token}, state) do
    case state.zones[key] do
      %Zone{token: ^token, permanent?: permanent?} ->
        occupied? = Enum.any?(state.members, fn {_guid, member} -> member.key == key end)
        state = if occupied? or permanent?, do: advance_zone(state, key), else: remove_zone(state, key)
        {:noreply, state}

      _stale ->
        {:noreply, state}
    end
  end

  defp handle_message({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state.members, state, fn
        {guid, %Member{monitor: ^monitor}}, state -> remove_member(state, guid)
        _entry, state -> state
      end)

    {:noreply, state}
  end

  defp ensure_zone(state, key) do
    if Map.has_key?(state.zones, key) do
      state
    else
      %{state | zones: Map.put(state.zones, key, schedule(%Zone{}, key, state.interval_ms))}
    end
  end

  defp advance_zone(state, {_world, zone_id} = key) do
    zone = state.zones[key]
    chances = state.lookup.(zone_id, Weather.season(state.date.()))
    weather = if zone.permanent?, do: zone.weather, else: Weather.advance(zone.weather, chances, state.sample.())
    updated = schedule(%{zone | weather: weather}, key, state.interval_ms)
    state = %{state | zones: Map.put(state.zones, key, updated)}
    if weather != zone.weather, do: broadcast(state, key, weather)
    state
  end

  defp schedule(zone, key, interval_ms) do
    if zone.timer, do: Process.cancel_timer(zone.timer)
    token = make_ref()
    timer = Process.send_after(self(), {:roll, key, token}, interval_ms)
    %{zone | timer: timer, token: token, next_roll_at: Time.now() + interval_ms}
  end

  defp broadcast(state, key, weather) do
    Enum.each(state.members, fn
      {_guid, %Member{key: ^key, pid: pid, token: token}} -> send(pid, {:weather_changed, token, weather})
      _other -> :ok
    end)
  end

  defp remove_zone(state, key) do
    {zone, zones} = Map.pop(state.zones, key)
    if zone, do: Process.cancel_timer(zone.timer)
    %{state | zones: zones}
  end

  defp remove_member(state, guid) do
    {member, members} = Map.pop(state.members, guid)
    if member, do: Process.demonitor(member.monitor, [:flush])
    %{state | members: members}
  end

  defp sample do
    %{
      change: :rand.uniform(100) - 1,
      kind: :rand.uniform(100),
      radical: :rand.uniform(100) - 1,
      intensity: :rand.uniform(100) - 1,
      grade: :rand.uniform()
    }
  end
end
