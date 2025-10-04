defmodule ThistleTea.FollowPathBehavior do
  use GenServer

  require Logger

  defp get_next_point(state) do
    current = Map.get(state, :current_point, 0)
    max = Map.get(state, :waypoints, []) |> Enum.count()

    if current + 1 < max do
      current + 1
    else
      0
    end
  end

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  @impl GenServer
  def handle_cast(:movement_finished, %{state: :pathing} = state) do
    # TODO: handle orientation, script, text, etc.

    delay =
      Map.get(state, :waypoints, [])
      |> Enum.at(state.current_point)
      |> Map.get(:waittime, 0)

    next_point = get_next_point(state)
    timer = Process.send_after(self(), {:start_pathing_to, next_point}, delay)
    {:noreply, Map.put(state, :state, :waiting) |> Map.put(:timer, timer)}
  end

  @impl GenServer
  def handle_cast(:movement_finished, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:start_pathing_to, point}, %{state: :waiting} = state) do
    case Map.get(state, :waypoints, [])
         |> Enum.at(point) do
      %{
        position_x: x,
        position_y: y,
        position_z: z
      } ->
        GenServer.cast(state.pid, {:move_to, x, y, z})
        {:noreply, Map.put(state, :state, :pathing) |> Map.put(:current_point, point)}

      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:start_pathing_to, _point}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       behavior: __MODULE__,
       state: state.state,
       # current point is where we're currently going to
       current_point: state.current_point,
       # initial point is the first point we're going to
       initial_point: state.initial_point,
       waypoint_count: Map.get(state, :waypoints, []) |> Enum.count(),
       delay:
         Map.get(state, :waypoints, [])
         |> Enum.at(state.current_point)
         |> Map.get(:waittime, 0)
     }, state}
  end

  @impl GenServer
  def init(initial) do
    :telemetry.execute([:thistle_tea, :mob, :wake_up], %{guid: initial.guid})
    initial_point = Map.get(initial, :initial_point)
    timer = Process.send_after(self(), {:start_pathing_to, initial_point}, 0)
    {:ok, initial |> Map.put(:state, :waiting) |> Map.put(:timer, timer)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    :telemetry.execute([:thistle_tea, :mob, :try_sleep], %{guid: state.guid})
    # so when it starts up again, it'll resume
    GenServer.cast(state.pid, {:set_initial_point, state.current_point})
    :ok
  end
end
