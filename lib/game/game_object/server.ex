defmodule ThistleTea.Game.GameObject.Server do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.GameObject

  def start_link(%GameObject.Data{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%GameObject.Data{} = state) do
    Process.flag(:trap_exit, true)
    Entity.Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Entity.Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state), do: Entity.Core.remove_position(state)
end
