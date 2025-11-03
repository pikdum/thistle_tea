defmodule ThistleTea.Game.Network.Send do
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT, :SMSG_COMPRESSED_UPDATE_OBJECT]

  alias ThistleTea.Game.Network.Connection.Crypto
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThousandIsland.Socket

  require Logger

  def send_packet(%Packet{opcode: @smsg_update_object, payload: payload}, {socket, state}) do
    compressed_payload = :zlib.compress(payload)
    original_size = byte_size(payload)

    %Packet{
      opcode: @smsg_compressed_update_object,
      payload: <<original_size::little-size(32)>> <> compressed_payload
    }
    |> send_packet({socket, state})
  end

  def send_packet(%Packet{opcode: opcode, payload: payload}, {socket, state}) do
    Logger.debug("Sending: #{Opcodes.get(opcode)}")
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
