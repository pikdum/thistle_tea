defmodule ThistleTea.Game.World.System.GameEvent do
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.World.System.CellActivator

  @events MapSet.new([2])

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_events do
    GenServer.call(__MODULE__, :get_events)
  end

  def set_events(events) when is_list(events), do: set_events(MapSet.new(events))

  def set_events(%MapSet{} = events) do
    GenServer.call(__MODULE__, {:set_events, events})
  end

  def subscribe(%{internal: %Internal{event: event}}), do: subscribe(event)

  def subscribe(event) when is_integer(event) do
    :ok = Phoenix.PubSub.subscribe(ThistleTea.PubSub, "game_event:#{event}")
  end

  def subscribe(_), do: :ok

  @impl GenServer
  def init(_) do
    {:ok, %{events: @events}}
  end

  @impl GenServer
  def handle_call(:get_events, _from, state) do
    {:reply, MapSet.to_list(state.events), state}
  end

  @impl GenServer
  def handle_call({:set_events, new_events}, _from, %{events: old_events} = state) do
    notify(new_events, old_events)
    {:reply, :ok, %{state | events: new_events}}
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
