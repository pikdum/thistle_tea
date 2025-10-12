defmodule ThistleTea.Game.Mob.Server do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Game.Mob

  def start_link(%Mob.Data{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob.Data{internal: %FieldStruct.Internal{movement_type: movement_type}} = state) do
    Process.flag(:trap_exit, true)
    Entity.Core.set_position(state)

    if movement_type == 1 do
      Process.send_after(self(), :wander, :rand.uniform(6_000))
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Entity.Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Entity.Movement.move_to(state, {x, y, z})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:wander, state) do
    state = Entity.Movement.wander(state)
    duration = state.movement_block.duration || 0
    delay = duration + :rand.uniform(6_000) + 4_000
    Process.send_after(self(), :wander, delay)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def handle_call(:get_name, _from, state), do: {:reply, state.internal.name, state}

  @impl GenServer
  def terminate(_reason, state), do: Entity.Core.remove_position(state)
end
