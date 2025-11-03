defmodule ThistleTea.Game.Network.Send do
  alias ThistleTea.Game.Network.Connection.Crypto
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThousandIsland.Socket

  def send_packet(%Packet{opcode: opcode, payload: payload}, {socket, state}) do
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>
    {:ok, conn, header} = Crypto.encrypt_header(state.conn, header)
    Socket.send(socket, header <> payload)
    %{state | conn: conn}
  end

  def send_packet(message, {socket, state}) do
    packet = Message.to_packet(message)
    send_packet(packet, {socket, state})
  end
end
