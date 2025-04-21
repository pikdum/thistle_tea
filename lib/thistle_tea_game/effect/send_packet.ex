defmodule ThistleTeaGame.Effect.SendPacket do
  alias ThistleTeaGame.Connection

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
        socket
      ) do
  end
end
