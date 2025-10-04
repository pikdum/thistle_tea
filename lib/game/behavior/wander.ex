defmodule ThistleTea.WanderBehavior do
  use GenServer

  alias ThistleTea.Pathfinding

  require Logger

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  @impl GenServer
  def handle_cast(:movement_finished, %{state: :wandering} = state) do
    timer = Process.send_after(self(), :start_wandering, :rand.uniform(6_000) + 4_000)
    {:noreply, Map.put(state, :state, :waiting) |> Map.put(:timer, timer)}
  end

  @impl GenServer
  def handle_cast(:movement_finished, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:start_wandering, %{state: :waiting} = state) do
    case Pathfinding.find_random_point_around_circle(
           state.map,
           {state.x0, state.y0, state.z0},
           state.wander_distance
         ) do
      {x, y, z} ->
        GenServer.cast(state.pid, {:move_to, x, y, z})
        {:noreply, Map.put(state, :state, :wandering)}

      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:start_wandering, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       behavior: __MODULE__,
       state: state.state,
       x0: state.x0,
       y0: state.y0,
       z0: state.z0,
       wander_distance: state.wander_distance
     }, state}
  end

  @impl GenServer
  def init(initial) do
    :telemetry.execute([:thistle_tea, :mob, :wake_up], %{guid: initial.guid})
    timer = Process.send_after(self(), :start_wandering, :rand.uniform(6_000))
    {:ok, initial |> Map.put(:state, :waiting) |> Map.put(:timer, timer)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    :telemetry.execute([:thistle_tea, :mob, :try_sleep], %{guid: state.guid})
    :ok
  end
end
