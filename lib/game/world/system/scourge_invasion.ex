defmodule ThistleTea.Game.World.System.ScourgeInvasion do
  @moduledoc """
  Drives the Scourge Invasion (`Core.GameEvent.ScourgeInvasion`). Like
  vmangos, whose `game_event` rows ship the invasion disabled, it starts off;
  `enable/1` lets the Scourge in and `disable/1` calls them off. While it runs,
  a pass every twenty seconds replays vmangos's controller: an attacked zone
  gets a Mouth of Kel'Thuzad that stands over it in a storm, announces the
  attack, and holds the zone's event open, and a zone whose necropolises have
  all fallen counts a victory as the Mouth departs. The attack clock and
  tallies live in vmangos's server variables, and every change to them goes
  out to all players as world states.
  """
  use GenServer

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion, as: Invasion
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Camp
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Zone
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Weather
  alias ThistleTea.Game.World.Topics

  require Logger

  @update_ms 20_000
  @mouth 16_995
  @dead_despawn 7
  @zone_start 7
  @zone_stop 8
  @storm_grade 0.25

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def enable(server \\ __MODULE__), do: GenServer.call(server, {:enable, true})

  def disable(server \\ __MODULE__), do: GenServer.call(server, {:enable, false})

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  def attack(name, server \\ __MODULE__) when is_atom(name), do: GenServer.call(server, {:attack, name})

  def necropolis_fell(zone_id, server \\ __MODULE__) when is_integer(zone_id),
    do: GenServer.cast(server, {:necropolis_fell, zone_id})

  def world_states(table \\ ServerVariables, game_events \\ GameEvent) do
    if Invasion.invasion_event() in GameEvent.active_events(game_events),
      do: Invasion.world_states(variables(table)),
      else: []
  end

  def summon_entries, do: [@mouth | Camp.summon_entries()]

  @impl GenServer
  def init(opts) do
    state = %{
      enabled?: false,
      variables: Keyword.get(opts, :variables, ServerVariables),
      game_events: Keyword.get(opts, :game_events, GameEvent),
      weather: Keyword.get(opts, :weather, Weather),
      clock: Keyword.get(opts, :clock, fn -> System.os_time(:second) end),
      rolls: Keyword.get(opts, :rolls, Rolls.system()),
      update_ms: Keyword.get(opts, :update_ms, @update_ms),
      summon: Keyword.get(opts, :summon, &summon_mouth/1),
      mouths: %{},
      timer: nil,
      states: nil,
      topic: Keyword.get(opts, :topic, Topics.world_states())
    }

    enabled? = Keyword.get(opts, :enabled?, Application.get_env(:thistle_tea, :scourge_invasion, false))
    {:ok, if(enabled?, do: turn_on(state), else: state)}
  end

  @impl GenServer
  def handle_call({:enable, true}, _from, %{enabled?: true} = state), do: {:reply, :ok, state}
  def handle_call({:enable, true}, _from, state), do: {:reply, :ok, turn_on(state)}
  def handle_call({:enable, false}, _from, %{enabled?: false} = state), do: {:reply, :ok, state}
  def handle_call({:enable, false}, _from, state), do: {:reply, :ok, turn_off(state)}

  def handle_call(:status, _from, state) do
    variables = variables(state.variables)
    now = state.clock.()

    zones =
      for zone <- Invasion.zones() do
        %{
          name: zone.name,
          attacked?: Map.has_key?(state.mouths, zone.name),
          remaining: Invasion.remaining(variables, zone),
          next_attack_s: max(Invasion.attack_time(variables, zone) - now, 0)
        }
      end

    {:reply, %{enabled?: state.enabled?, victories: Invasion.victories(variables), zones: zones}, state}
  end

  def handle_call({:attack, name}, _from, %{enabled?: true} = state) do
    case Invasion.zone(name) do
      %Zone{} = zone when not is_map_key(state.mouths, name) ->
        variables = Invasion.start(variables(state.variables), zone)
        state = state |> store(variables) |> start_zone(zone) |> drive() |> publish()
        {:reply, :ok, state}

      %Zone{} ->
        {:reply, {:error, :already_attacked}, state}

      nil ->
        {:reply, {:error, :unknown_zone}, state}
    end
  end

  def handle_call({:attack, _name}, _from, state), do: {:reply, {:error, :disabled}, state}

  @impl GenServer
  def handle_cast({:necropolis_fell, zone_id}, state) do
    case Invasion.zone_for(zone_id) do
      %Zone{} = zone ->
        variables = Invasion.necropolis_fell(variables(state.variables), zone)
        {:noreply, state |> store(variables) |> publish()}

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:update, timer}, %{timer: timer, enabled?: true} = state) do
    {:noreply, state |> update() |> schedule()}
  rescue
    error ->
      Logger.error("Scourge Invasion update failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, schedule(state)}
  end

  def handle_info({:update, _timer}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.mouths, fn {_name, mouth} -> mouth.monitor == ref end) do
      {name, _mouth} -> {:noreply, %{state | mouths: Map.delete(state.mouths, name)}}
      nil -> {:noreply, state}
    end
  end

  defp turn_on(state) do
    state = %{state | enabled?: true}
    now = state.clock.()
    state |> pass(&Invasion.begin(&1, &2, now)) |> schedule()
  end

  defp turn_off(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = Enum.reduce(Invasion.zones(), state, &end_zone(&2, &1, :silently))
    state = store(state, Invasion.reset(variables(state.variables), state.clock.()))
    %{state | enabled?: false, timer: nil} |> drive() |> publish()
  end

  defp update(state) do
    now = state.clock.()
    pass(state, &Invasion.update(&1, &2, now, state.rolls))
  end

  defp pass(state, step) do
    variables = variables(state.variables)

    if Invasion.over?(variables) do
      state = Enum.reduce(Invasion.zones(), state, &end_zone(&2, &1, :silently))
      state |> store(Invasion.reset(variables, state.clock.())) |> drive() |> publish()
    else
      {variables, _active, actions} = step.(variables, MapSet.new(Map.keys(state.mouths)))
      state = store(state, variables)

      actions
      |> Enum.reduce(state, fn
        {:start, zone}, state -> start_zone(state, zone)
        {:stop, zone}, state -> end_zone(state, zone, :defeated)
      end)
      |> drive()
      |> publish()
    end
  end

  defp start_zone(state, %Zone{} = zone) do
    case state.summon.(zone) do
      {:ok, guid, pid} ->
        Entity.script_event(guid, @zone_start, 0)
        storm(state, zone)
        mouth = %{guid: guid, monitor: Process.monitor(pid)}
        %{state | mouths: Map.put(state.mouths, zone.name, mouth)}

      :error ->
        Logger.error("Scourge Invasion could not summon the Mouth of Kel'Thuzad over #{zone.name}")
        state
    end
  end

  defp end_zone(state, %Zone{} = zone, ending) do
    case Map.pop(state.mouths, zone.name) do
      {%{guid: guid, monitor: monitor}, mouths} ->
        Process.demonitor(monitor, [:flush])
        depart(guid, ending)
        calm(state, zone)
        %{state | mouths: mouths}

      {nil, _mouths} ->
        state
    end
  end

  defp depart(guid, :silently) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, {:ai_script_steps, [%ScriptStep{command: :despawn}], nil})
      nil -> :ok
    end
  end

  defp depart(guid, :defeated), do: Entity.script_event(guid, @zone_stop, 0)

  defp storm(%{weather: nil}, _zone), do: :ok

  defp storm(state, %Zone{} = zone),
    do: Weather.set(WorldRef.open(zone.map_id), zone.zone_id, :storm, @storm_grade, true, state.weather)

  defp calm(%{weather: nil}, _zone), do: :ok
  defp calm(state, %Zone{} = zone), do: Weather.resume(WorldRef.open(zone.map_id), zone.zone_id, state.weather)

  defp drive(state) do
    active = MapSet.new(Map.keys(state.mouths))
    :ok = GameEvent.drive(Invasion.driven(variables(state.variables), active, state.enabled?), state.game_events)
    state
  end

  defp publish(state) do
    states = if state.enabled?, do: Invasion.world_states(variables(state.variables)), else: off_states()

    if states != state.states do
      changed = if state.states, do: states -- state.states, else: states
      Topics.publish(state.topic, {:world_states_changed, changed})
    end

    %{state | states: states}
  end

  defp off_states, do: Enum.map(Invasion.world_states(%{}), fn {id, _value} -> {id, 0} end)

  defp schedule(state) do
    timer = make_ref()
    Process.send_after(self(), {:update, timer}, state.update_ms)
    %{state | timer: timer}
  end

  defp store(state, variables) do
    Enum.each(variables, fn {index, value} ->
      if ServerVariables.get(index, state.variables) != value,
        do: :ok = ServerVariables.put(index, value, state.variables)
    end)

    state
  end

  defp variables(table), do: Map.new(Invasion.variables(), &{&1, ServerVariables.get(&1, table)})

  defp summon_mouth(%Zone{} = zone) do
    world = WorldRef.open(zone.map_id)

    with %{} = mouth <- SummonLoader.build(@mouth, world, zone.mouth, despawn_type: @dead_despawn),
         {:ok, pid} <- MobLoader.start_mob(mouth) do
      {:ok, mouth.object.guid, pid}
    else
      _failed -> :error
    end
  end
end
