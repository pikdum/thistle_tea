defmodule ThistleTea.Game.GameObject.Server do
  use GenServer

  alias ThistleTea.Game.GameObject

  @impl GenServer
  def init(%GameObject.Data{} = state) do
    GameObject.Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = GameObject.Core.update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end
end
