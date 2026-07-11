defmodule ThistleTea.Game.World.System.GameEvent do
  @moduledoc """
  Tracks which seasonal/world game events are active and notifies subscribed
  event-gated spawns when their event starts or stops.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.World.Loader.GameEvent, as: GameEventLoader
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.GameEvent.Schedule

  @max_timer_ms 2_147_483_647
  @tick :scheduled_game_event_transition

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def get_events(server \\ __MODULE__) do
    GenServer.call(server, :get_events)
  end

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  def set_events(events, server \\ __MODULE__)

  def set_events(events, server) when is_list(events), do: set_events(MapSet.new(events), server)

  def set_events(%MapSet{} = events, server) do
    GenServer.call(server, {:set_events, events})
  end

  def subscribe(%{internal: %Internal{event: event}}), do: subscribe(event)

  def subscribe(event) when is_integer(event) do
    :ok = Phoenix.PubSub.subscribe(ThistleTea.PubSub, "game_event:#{event}")
  end

  def subscribe(_), do: :ok

  @impl GenServer
  def init(opts) do
    schedule = load_schedule(opts)
    now = Keyword.get(opts, :now, &DateTime.utc_now/0)

    on_change = Keyword.get(opts, :on_change, &apply_events/2)

    state = %{events: MapSet.new(), schedule: schedule, now: now, on_change: on_change, timer_ref: nil}
    {:ok, sync_schedule(state)}
  end

  @impl GenServer
  def handle_call(:get_events, _from, state) do
    {:reply, Enum.sort(MapSet.to_list(state.events)), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, schedule_status(state, state.now.()), state}
  end

  @impl GenServer
  def handle_call({:set_events, new_events}, _from, %{events: old_events} = state) do
    state.on_change.(new_events, old_events)
    {:reply, :ok, %{state | events: new_events}}
  end

  @impl GenServer
  def handle_info(@tick, state) do
    {:noreply, sync_schedule(%{state | timer_ref: nil})}
  end

  defp load_schedule(opts) do
    case Keyword.fetch(opts, :schedule) do
      {:ok, %Schedule{} = schedule} -> schedule
      :error -> load_configured_schedule(Keyword.get(opts, :load_schedule, true))
    end
  end

  defp load_configured_schedule(true), do: GameEventLoader.load_schedule()
  defp load_configured_schedule(false), do: Schedule.new([])
  defp load_configured_schedule(loader) when is_function(loader, 0), do: loader.()

  defp sync_schedule(%{schedule: %Schedule{} = schedule, now: now} = state) do
    current_time = now.()
    scheduled_events = MapSet.new(Schedule.active_events(schedule, current_time))

    if scheduled_events != state.events do
      state.on_change.(scheduled_events, state.events)
    end

    %{state | events: scheduled_events}
    |> schedule_next_transition(current_time)
  end

  defp schedule_next_transition(state, now) do
    case Schedule.next_transition(state.schedule, now) do
      %DateTime{} = transition ->
        delay = max(DateTime.diff(transition, now, :millisecond), 1) |> min(@max_timer_ms)
        %{state | timer_ref: Process.send_after(self(), @tick, delay)}

      nil ->
        state
    end
  end

  defp schedule_status(state, now) do
    entries = Map.new(state.schedule.entries, &{&1.id, &1})
    active = entries_for(state.events, entries)

    next =
      case Schedule.next_transition(state.schedule, now) do
        %DateTime{} = at -> transition_status(state.schedule, state.events, entries, at)
        nil -> nil
      end

    %{active: active, next: next}
  end

  defp transition_status(schedule, active_events, entries, at) do
    next_events = MapSet.new(Schedule.active_events(schedule, at))

    %{
      at: at,
      starts: next_events |> MapSet.difference(active_events) |> entries_for(entries),
      stops: active_events |> MapSet.difference(next_events) |> entries_for(entries)
    }
  end

  defp entries_for(ids, entries) do
    ids
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(entries, &1))
  end

  defp apply_events(new_events, old_events) do
    notify(new_events, old_events)
    SpawnPool.refresh_all(MapSet.to_list(new_events))
  end

  defp notify(%MapSet{} = new_events, %MapSet{} = old_events) do
    start = MapSet.difference(new_events, old_events)
    stop = MapSet.difference(old_events, new_events)

    # not implemented yet
    # but some models change depending on current event
    Enum.each(start, &notify(&1, {:event_start, &1}))

    # despawn
    Enum.each(stop, &notify(&1, {:event_stop, &1}))

    # spawn
    if start != MapSet.new() do
      CellActivator.invalidate()
    end
  end

  defp notify(event, message) do
    Phoenix.PubSub.broadcast(ThistleTea.PubSub, "game_event:#{event}", message)
  end
end
