defmodule ThistleTeaGame.ServerPacket.SmsgCharEnum do
  use ThistleTeaGame.ServerPacket, opcode: :SMSG_CHAR_ENUM

  defstruct characters: []

  @impl ServerPacket
  def encode(%__MODULE__{characters: characters}) do
    <<Enum.count(characters)>>
    |> ServerPacket.build(@opcode)
  end
end
