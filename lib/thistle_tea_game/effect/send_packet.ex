defmodule ThistleTeaGame.Effect.SendPacket do
  alias ThousandIsland.Socket
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.ServerPacket

  defstruct [
    :packet
  ]

  defimpl ThistleTeaGame.Effect do
    def process(effect, conn, socket),
      do: ThistleTeaGame.Effect.SendPacket.process(effect, conn, socket)
  end

  def process(
        %__MODULE__{
          packet: packet
        },
        %Connection{} = conn,
        %Socket{} = socket
      ) do
    %ServerPacket{
      opcode: opcode,
      size: size,
      payload: payload
    } = ServerPacket.Protocol.encode(packet)

    header = <<size::big-size(16), opcode::little-size(16)>>
    {:ok, conn, encrypted_header} = Connection.Crypto.encrypt_header(conn, header)
    Socket.send(socket, encrypted_header <> payload)
    {:ok, conn}
  end
end
