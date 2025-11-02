defmodule ThistleTea.Game.Entity.Server.Mob do
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob{internal: %Internal{movement_type: movement_type}} = state) do
    Process.flag(:trap_exit, true)
    Core.set_position(state)

    case movement_type do
      1 -> Process.send_after(self(), :wander, :rand.uniform(6_000))
      2 -> Process.send_after(self(), :follow_waypoint_route, 0)
      _ -> :ok
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:wander, state) do
    state = Movement.wander(state)
    delay = Movement.wander_delay(state)
    Process.send_after(self(), :wander, delay)
    {:noreply, state}
  rescue
    _ -> {:noreply, state}
  end

  @impl GenServer
  def handle_info(:follow_waypoint_route, %Mob{internal: %Internal{waypoint_route: nil}} = state) do
    {:noreply, state}
  end

  def handle_info(:follow_waypoint_route, state) do
    state = Movement.follow_waypoint_route(state)
    delay = Movement.follow_waypoint_route_delay(state)
    Process.send_after(self(), :follow_waypoint_route, delay)
    {:noreply, state}
  rescue
    _ -> {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def handle_call(:get_name, _from, state), do: {:reply, state.internal.name, state}

  @impl GenServer
  def terminate(_reason, state), do: Core.remove_position(state)
end
