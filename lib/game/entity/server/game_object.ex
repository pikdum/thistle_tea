defmodule ThistleTea.Game.Entity.Server.GameObject do
  use GenServer

  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Core

  def start_link(%GameObject{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%GameObject{} = state) do
    Process.flag(:trap_exit, true)
    Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state), do: Core.remove_position(state)
end
