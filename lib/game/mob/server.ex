defmodule ThistleTea.Game.Mob.Server do
  use GenServer

  alias ThistleTea.Game.Mob

  def start_link(%Mob.Data{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob.Data{} = state) do
    Process.flag(:trap_exit, true)
    Mob.Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Mob.Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def handle_call(:get_name, _from, state), do: {:reply, state.internal.name, state}

  @impl GenServer
  def terminate(_reason, state), do: Mob.Core.terminate(state)
end
