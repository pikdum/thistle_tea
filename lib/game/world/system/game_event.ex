defmodule ThistleTea.Game.World.System.GameEvent do
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal

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

  def subscribe(%{internal: %Internal{} = %{event: event}}), do: subscribe(event)

  def subscribe(event) when is_integer(event) do
    Phoenix.PubSub.subscribe(ThistleTea.PubSUb, "game_event:#{event}")
  end

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
    new_events
    |> MapSet.difference(old_events)
    |> Enum.each(&notify(&1, :up))

    old_events
    |> MapSet.difference(new_events)
    |> Enum.each(&notify(&1, :down))
  end

  defp notify(event, message) do
    Phoenix.PubSub.broadcast(ThistleTea.PubSub, "game_event:#{event}", message)
  end
end
