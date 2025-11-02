defmodule ThistleTea.Game.Network do
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet

  def send_packet(pid, opcode, payload) when is_pid(pid) do
    GenServer.cast(pid, {:send_packet, opcode, payload})
  end

  def send_packet(pid, %Packet{opcode: opcode, payload: payload}) when is_pid(pid) do
    send_packet(pid, opcode, payload)
  end

  def send_packet(pid, message) when is_pid(pid) do
    packet = message |> Message.to_packet()
    send_packet(pid, packet.opcode, packet.payload)
  end

  def send_packet(opcode, payload) do
    send_packet(self(), opcode, payload)
  end

  def send_packet(%Packet{opcode: opcode, payload: payload}) do
    send_packet(self(), opcode, payload)
  end

  def send_packet(message) do
    send_packet(self(), message)
  end
end
