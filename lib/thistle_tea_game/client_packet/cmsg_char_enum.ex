defmodule ThistleTeaGame.ClientPacket.CmsgCharEnum do
  use ThistleTeaGame.ClientPacket, opcode: :CMSG_CHAR_ENUM

  defstruct []

  @impl ClientPacket
  def handle(%__MODULE__{}, %Connection{} = conn) do
    effect = %Effect.SendPacket{
      packet: %ServerPacket.SmsgCharEnum{characters: []}
    }

    {:ok, conn |> Connection.add_effect(effect)}
  end

  @impl ClientPacket
  def decode(%ClientPacket{}) do
    {:ok, %__MODULE__{}}
  end
end
