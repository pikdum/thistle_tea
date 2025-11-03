defmodule ThistleTea.Game.Network do
  def send_packet(packet, pid \\ self())

  def send_packet(packets, pid) when is_list(packets) do
    Enum.each(packets, fn packet -> send_packet(packet, pid) end)
  end

  def send_packet(packet, pid) do
    GenServer.cast(pid, {:send_packet, packet})
  end
end
