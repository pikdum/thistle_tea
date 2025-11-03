defmodule ThistleTea.Game.Network do
  def send_packet(packet, pid \\ self()) do
    GenServer.cast(pid, {:send_packet, packet})
  end
end
