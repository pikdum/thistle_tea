defmodule ThistleTea.AttackBehavior do
  use GenServer
  require Logger

  @update_interval 100

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  @impl GenServer
  def handle_cast(:movement_finished, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:start_movement, %{state: :waiting} = state) do
    with target when not is_nil(target) <- Map.get(state, :target),
         [{^target, _pid, _map, x, y, z}] <- :ets.lookup(:entities, target) do
      GenServer.cast(state.pid, {:move_to, x, y, z})
      Process.send_after(self(), :update_movement, @update_interval)
      {:noreply, state |> Map.put(:state, :moving) |> Map.put(:target_position, {x, y, z})}
    else
      _ -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:update_movement, %{state: :moving} = state) do
    with target when not is_nil(target) <- Map.get(state, :target),
         guid <- Map.get(state, :guid),
         [{^guid, _pid, map, x0, y0, z0}] <- :ets.lookup(:entities, guid),
         [{^target, _pid, ^map, x1, y1, z1}] <- :ets.lookup(:entities, target),
         false <- ThistleTea.Util.within_range({x0, y0, z0}, {x1, y1, z1}, 1),
         false <- ThistleTea.Util.within_range({x1, y1, z1}, Map.get(state, :target_position), 1) do
      GenServer.cast(state.pid, {:move_to, x1, y1, z1})
      Process.send_after(self(), :update_movement, @update_interval)
      {:noreply, state |> Map.put(:target_position, {x1, y1, z1})}
    else
      _ ->
        Process.send_after(self(), :update_movement, @update_interval)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply,
     %{
       behavior: __MODULE__,
       state: state.state,
       target: state.target
     }, state}
  end

  @impl GenServer
  def init(initial) do
    :telemetry.execute([:thistle_tea, :mob, :wake_up], %{guid: initial.guid})
    timer = Process.send_after(self(), :start_movement, 0)
    {:ok, initial |> Map.put(:state, :waiting) |> Map.put(:timer, timer)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    :telemetry.execute([:thistle_tea, :mob, :try_sleep], %{guid: state.guid})
    :ok
  end
end
