defmodule ThistleTea.Game.World.Battleground.Match do
  @moduledoc """
  Owns one battleground aggregate and serializes its timers and interactions.
  """
  use GenServer

  alias ThistleTea.Game.Battleground.Effects.ExitPlayers
  alias ThistleTea.Game.Battleground.Result
  alias ThistleTea.Game.Battleground.Rules
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.EffectSink
  alias ThistleTea.Game.World.Battleground.Spawns
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.GameEvent

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :world)}, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  def enter(server, guid, return_to), do: GenServer.call(server, {:enter, guid, return_to})
  def reserve(server, reservations), do: GenServer.call(server, {:reserve, reservations})
  def reconnect(server, guid), do: GenServer.call(server, {:reconnect, guid})
  def leave(server, guid, position, dropped_guid), do: GenServer.call(server, {:leave, guid, position, dropped_guid})

  def use_game_object(server, guid, object_guid, entry, position) do
    GenServer.call(server, {:use_game_object, guid, object_guid, entry, position})
  end

  def area_trigger(server, guid, trigger_id, position, dropped_guid) do
    GenServer.call(server, {:area_trigger, guid, trigger_id, position, dropped_guid})
  end

  def player_died(server, defeat, dropped_guid) do
    GenServer.cast(server, {:player_died, defeat, dropped_guid})
  end

  def creature_died(server, defeat), do: GenServer.cast(server, {:creature_died, defeat})

  def disconnect(server, guid, position, dropped_guid) do
    GenServer.cast(server, {:disconnect, guid, position, dropped_guid})
  end

  def queue_resurrection(server, guid), do: GenServer.cast(server, {:queue_resurrection, guid})
  def cancel_resurrection(server, guid), do: GenServer.cast(server, {:cancel_resurrection, guid})
  def start_now(server), do: GenServer.call(server, :start_now)
  def snapshot(server), do: GenServer.call(server, :snapshot)
  def world_states(server), do: GenServer.call(server, :world_states)
  def scoreboard(server), do: GenServer.call(server, :scoreboard)
  def spirit_healer_time(server), do: GenServer.call(server, :spirit_healer_time)
  def supply_allowed?(server, guid, entry), do: GenServer.call(server, {:supply_allowed, guid, entry})

  @impl GenServer
  def init(opts) do
    now = Keyword.get(opts, :now, Time.now())
    world = Keyword.fetch!(opts, :world)
    rules = Rules.fetch!(world.map_id)
    Spawns.open(world)

    options =
      Keyword.get(opts, :match_options, [])
      |> Keyword.put_new_lazy(:weekend?, fn -> Rules.weekend_event(world.map_id) in GameEvent.get_events() end)

    result =
      rules.new(
        Keyword.fetch!(opts, :world),
        Keyword.fetch!(opts, :client_instance_id),
        Keyword.fetch!(opts, :bracket),
        Keyword.fetch!(opts, :template),
        Keyword.fetch!(opts, :reservations),
        now,
        options
      )

    owner = self()

    state = %{
      match: result.match,
      rules: rules,
      manager: Keyword.fetch!(opts, :manager),
      effect_sink:
        Keyword.get(opts, :effect_sink) || fn match, effects -> EffectSink.emit(match, effects, owner: owner) end
    }

    {:ok, apply_result(state, result)}
  end

  @impl GenServer
  def handle_call({:enter, guid, return_to}, _from, state) do
    result = state.rules.enter(state.match, guid, return_to)
    {:reply, player(result.match, guid), apply_result(state, result)}
  end

  def handle_call({:reserve, reservations}, _from, state) do
    result = state.rules.reserve(state.match, reservations)
    {:reply, :ok, apply_result(state, result)}
  end

  def handle_call({:reconnect, guid}, _from, state) do
    result = state.rules.reconnect(state.match, guid)
    {:reply, player(result.match, guid), apply_result(state, result)}
  end

  def handle_call({:leave, guid, position, dropped_guid}, _from, state) do
    dropped_guid = dropped_flag_guid(state, guid, dropped_guid)
    result = state.rules.leave(state.match, guid, position, dropped_guid)
    notify_left(state.manager, guid)
    state = state |> apply_result(result) |> shutdown_if_empty()
    {:reply, :ok, state}
  end

  def handle_call({:use_game_object, guid, object_guid, entry, position}, _from, state) do
    events = object_events(state.match.world, object_guid)

    case state.rules.use_game_object(state.match, guid, object_guid, entry, position, Time.now(), events) do
      {:handled, result} -> {:reply, :handled, apply_result(state, result)}
      {:unhandled, result} -> {:reply, :unhandled, apply_result(state, result)}
    end
  end

  def handle_call({:area_trigger, guid, trigger_id, position, dropped_guid}, _from, state) do
    case state.rules.area_trigger(state.match, guid, trigger_id, Time.now()) do
      {:handled, result} ->
        {:reply, :handled, apply_result(state, result)}

      {:leave, return_to} ->
        result = state.rules.leave(state.match, guid, position, dropped_guid)
        notify_left(state.manager, guid)
        state = state |> apply_result(result) |> shutdown_if_empty()
        state.effect_sink.(state.match, [%ExitPlayers{destinations: %{guid => return_to}}])
        {:reply, :handled, state}

      :unhandled ->
        {:reply, :unhandled, state}
    end
  end

  def handle_call(:start_now, _from, %{match: %{phase: :countdown}} = state) do
    result = state.rules.handle_timer(state.match, :start, Time.now())
    {:reply, :ok, apply_result(state, result)}
  end

  def handle_call(:start_now, _from, state), do: {:reply, {:error, :not_counting_down}, state}

  def handle_call(:snapshot, _from, state), do: {:reply, state.match, state}
  def handle_call(:world_states, _from, state), do: {:reply, state.rules.world_states(state.match), state}
  def handle_call(:scoreboard, _from, state), do: {:reply, state.rules.scoreboard_snapshot(state.match), state}

  def handle_call(:spirit_healer_time, _from, state) do
    {:reply, state.rules.next_resurrection_ms(state.match, Time.now()), state}
  end

  def handle_call({:supply_allowed, guid, entry}, _from, %{match: %{world: %{map_id: 30}}} = state) do
    {:reply, state.rules.supply_allowed?(state.match, guid, entry), state}
  rescue
    _error -> {:reply, false, state}
  end

  def handle_call({:supply_allowed, _guid, _entry}, _from, state), do: {:reply, false, state}

  @impl GenServer
  def handle_cast({:player_died, defeat, dropped_guid}, state) do
    dropped_guid = dropped_flag_guid(state, defeat.victim_guid, dropped_guid)
    result = state.rules.player_died(state.match, defeat, dropped_guid)
    {:noreply, apply_result(state, result)}
  end

  def handle_cast({:creature_died, defeat}, state) do
    {:noreply, apply_result(state, state.rules.creature_died(state.match, defeat, Time.now()))}
  rescue
    error ->
      Logger.error("Battleground creature death failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast({:disconnect, guid, position, dropped_guid}, state) do
    dropped_guid = dropped_flag_guid(state, guid, dropped_guid)
    {:noreply, apply_result(state, state.rules.disconnect(state.match, guid, position, dropped_guid))}
  end

  def handle_cast({:queue_resurrection, guid}, state) do
    {:noreply, apply_result(state, state.rules.queue_resurrection(state.match, guid))}
  end

  def handle_cast({:cancel_resurrection, guid}, state) do
    {:noreply, apply_result(state, state.rules.cancel_resurrection(state.match, guid))}
  end

  @impl GenServer
  def handle_info({:battleground_timer, key}, state) do
    {:noreply, apply_result(state, state.rules.handle_timer(state.match, key, Time.now()))}
  end

  def handle_info(:shutdown, state), do: {:stop, :normal, state}

  @impl GenServer
  def terminate(_reason, state) do
    SpawnPool.stop_world(state.match.world)
    World.stop_world_entities(state.match.world)
    CellActivator.deactivate_world(state.match.world)
    Spawns.close(state.match.world)
    :ok
  end

  defp apply_result(state, %Result{} = result) do
    Enum.each(result.timers, fn {key, delay_ms} -> Process.send_after(self(), {:battleground_timer, key}, delay_ms) end)
    state.effect_sink.(result.match, result.effects)
    if Enum.any?(result.effects, &match?(%ExitPlayers{}, &1)), do: Process.send_after(self(), :shutdown, 5_000)
    %{state | match: result.match}
  end

  defp object_events(world, guid) do
    case Metadata.query(guid, [:db_guid]) do
      %{db_guid: db_guid} when is_integer(db_guid) -> BattlegroundLoader.bindings(world.map_id, :game_object, db_guid)
      _missing -> []
    end
  end

  defp player(match, guid), do: Map.get(match.players, guid)
  defp notify_left(manager, guid), do: GenServer.cast(manager, {:match_player_left, self(), guid})

  defp shutdown_if_empty(state) do
    if map_size(state.match.players) == 0, do: send(self(), :shutdown)
    state
  end

  defp dropped_flag_guid(state, guid, _requested_guid) do
    case state.rules.carried_flag(state.match, guid) do
      :alliance -> Guid.runtime(:game_object, 179_785)
      :horde -> Guid.runtime(:game_object, 179_786)
      nil -> nil
    end
  end
end
