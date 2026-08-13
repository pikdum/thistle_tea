defmodule ThistleTea.Game.World.Battleground.Match do
  @moduledoc """
  Owns one battleground aggregate and serializes its timers and interactions.
  """
  use GenServer

  alias ThistleTea.Game.Battleground.Effects.ExitPlayers
  alias ThistleTea.Game.Battleground.WarsongGulch
  alias ThistleTea.Game.Battleground.WarsongGulch.Result
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.EffectSink
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.CellActivator

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

  def player_died(server, victim_guid, killer_guid, position, dropped_guid) do
    GenServer.cast(server, {:player_died, victim_guid, killer_guid, position, dropped_guid})
  end

  def disconnect(server, guid, position, dropped_guid) do
    GenServer.cast(server, {:disconnect, guid, position, dropped_guid})
  end

  def queue_resurrection(server, guid), do: GenServer.cast(server, {:queue_resurrection, guid})
  def snapshot(server), do: GenServer.call(server, :snapshot)
  def world_states(server), do: GenServer.call(server, :world_states)
  def scoreboard(server), do: GenServer.call(server, :scoreboard)
  def spirit_healer_time(server), do: GenServer.call(server, :spirit_healer_time)

  @impl GenServer
  def init(opts) do
    now = Keyword.get(opts, :now, Time.now())

    result =
      WarsongGulch.new(
        Keyword.fetch!(opts, :world),
        Keyword.fetch!(opts, :client_instance_id),
        Keyword.fetch!(opts, :bracket),
        Keyword.fetch!(opts, :template),
        Keyword.fetch!(opts, :reservations),
        now,
        Keyword.get(opts, :match_options, [])
      )

    state = %{
      match: result.match,
      manager: Keyword.fetch!(opts, :manager),
      effect_sink: Keyword.get(opts, :effect_sink, &EffectSink.emit/2)
    }

    {:ok, apply_result(state, result)}
  end

  @impl GenServer
  def handle_call({:enter, guid, return_to}, _from, state) do
    result = WarsongGulch.enter(state.match, guid, return_to)
    {:reply, player(result.match, guid), apply_result(state, result)}
  end

  def handle_call({:reserve, reservations}, _from, state) do
    result = WarsongGulch.reserve(state.match, reservations)
    {:reply, :ok, apply_result(state, result)}
  end

  def handle_call({:reconnect, guid}, _from, state) do
    result = WarsongGulch.reconnect(state.match, guid)
    {:reply, player(result.match, guid), apply_result(state, result)}
  end

  def handle_call({:leave, guid, position, dropped_guid}, _from, state) do
    dropped_guid = dropped_flag_guid(state.match, guid, dropped_guid)
    result = WarsongGulch.leave(state.match, guid, position, dropped_guid)
    notify_left(state.manager, guid)
    {:reply, :ok, apply_result(state, result)}
  end

  def handle_call({:use_game_object, guid, object_guid, entry, position}, _from, state) do
    case WarsongGulch.use_game_object(state.match, guid, object_guid, entry, position, Time.now()) do
      {:handled, result} -> {:reply, :handled, apply_result(state, result)}
      {:unhandled, result} -> {:reply, :unhandled, apply_result(state, result)}
    end
  end

  def handle_call({:area_trigger, guid, trigger_id, position, dropped_guid}, _from, state) do
    case WarsongGulch.area_trigger(state.match, guid, trigger_id, Time.now()) do
      {:handled, result} ->
        {:reply, :handled, apply_result(state, result)}

      {:leave, return_to} ->
        result = WarsongGulch.leave(state.match, guid, position, dropped_guid)
        notify_left(state.manager, guid)
        state = apply_result(state, result)
        state.effect_sink.(state.match, [%ExitPlayers{destinations: %{guid => return_to}}])
        {:reply, :handled, state}

      :unhandled ->
        {:reply, :unhandled, state}
    end
  end

  def handle_call(:snapshot, _from, state), do: {:reply, state.match, state}
  def handle_call(:world_states, _from, state), do: {:reply, WarsongGulch.world_states(state.match), state}
  def handle_call(:scoreboard, _from, state), do: {:reply, WarsongGulch.scoreboard(state.match), state}

  def handle_call(:spirit_healer_time, _from, state) do
    {:reply, WarsongGulch.next_resurrection_ms(state.match, Time.now()), state}
  end

  @impl GenServer
  def handle_cast({:player_died, victim_guid, killer_guid, position, dropped_guid}, state) do
    dropped_guid = dropped_flag_guid(state.match, victim_guid, dropped_guid)
    result = WarsongGulch.player_died(state.match, victim_guid, killer_guid, position, dropped_guid)
    {:noreply, apply_result(state, result)}
  end

  def handle_cast({:disconnect, guid, position, dropped_guid}, state) do
    dropped_guid = dropped_flag_guid(state.match, guid, dropped_guid)
    {:noreply, apply_result(state, WarsongGulch.disconnect(state.match, guid, position, dropped_guid))}
  end

  def handle_cast({:queue_resurrection, guid}, state) do
    {:noreply, apply_result(state, WarsongGulch.queue_resurrection(state.match, guid))}
  end

  @impl GenServer
  def handle_info({:battleground_timer, key}, state) do
    {:noreply, apply_result(state, WarsongGulch.handle_timer(state.match, key, Time.now()))}
  end

  def handle_info(:shutdown, state), do: {:stop, :normal, state}

  @impl GenServer
  def terminate(_reason, state) do
    SpawnPool.stop_world(state.match.world)
    World.stop_world_entities(state.match.world)
    CellActivator.deactivate_world(state.match.world)
    :ok
  end

  defp apply_result(state, %Result{} = result) do
    Enum.each(result.timers, fn {key, delay_ms} -> Process.send_after(self(), {:battleground_timer, key}, delay_ms) end)
    state.effect_sink.(result.match, result.effects)
    if Enum.any?(result.effects, &match?(%ExitPlayers{}, &1)), do: Process.send_after(self(), :shutdown, 5_000)
    %{state | match: result.match}
  end

  defp player(match, guid), do: Map.get(match.players, guid)
  defp notify_left(manager, guid), do: GenServer.cast(manager, {:match_player_left, self(), guid})

  defp dropped_flag_guid(match, guid, _requested_guid) do
    case WarsongGulch.carried_flag(match, guid) do
      :alliance -> Guid.runtime(:game_object, 179_785)
      :horde -> Guid.runtime(:game_object, 179_786)
      nil -> nil
    end
  end
end
