defmodule ThistleTea.Game.Network.Send do
  @moduledoc """
  Writes packets to the socket with encrypted headers. Update-object
  payloads larger than 128 bytes go out as SMSG_COMPRESSED_UPDATE_OBJECT at
  zlib's fastest level, matching vmangos' `Compression.Level` and
  `Compression.Update.Size` defaults; smaller ones stay uncompressed.
  """
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT, :SMSG_COMPRESSED_UPDATE_OBJECT]

  alias ThistleTea.Game.Network.Connection.Crypto
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThousandIsland.Socket

  @compression_level 1
  @compression_threshold 128

  def send_packet(%Packet{} = packet, {socket, state}) do
    %Packet{opcode: opcode, payload: payload} = compress(packet)
    size = byte_size(payload) + 2
    header = size_header(size) <> <<opcode::little-size(16)>>
    {:ok, conn, header} = Crypto.encrypt_header(state.conn, header)
    result = Socket.send(socket, header <> payload)

    :telemetry.execute(
      [:thistle_tea, :network, :send],
      %{bytes: byte_size(header) + byte_size(payload), uncompressed_bytes: byte_size(packet.payload)},
      %{result: result}
    )

    %{state | conn: conn}
  end

  def send_packet(message, {socket, state}) do
    message
    |> Message.to_packet()
    |> send_packet({socket, state})
  end

  def compress(%Packet{opcode: @smsg_update_object, payload: payload})
      when byte_size(payload) > @compression_threshold do
    %Packet{
      opcode: @smsg_compressed_update_object,
      payload: <<byte_size(payload)::little-size(32)>> <> deflate(payload)
    }
  end

  def compress(%Packet{} = packet), do: packet

  defp deflate(payload) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, @compression_level)
      compressed = :zlib.deflate(z, payload, :finish)
      :ok = :zlib.deflateEnd(z)
      IO.iodata_to_binary(compressed)
    after
      :zlib.close(z)
    end
  end

  defp size_header(size) when size > 0x7FFF, do: <<Bitwise.bor(size, 0x800000)::big-size(24)>>
  defp size_header(size), do: <<size::big-size(16)>>
end
