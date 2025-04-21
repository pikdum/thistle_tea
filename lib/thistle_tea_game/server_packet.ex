defmodule ThistleTeaGame.ServerPacket do
  defstruct [
    :opcode,
    :size,
    :payload
  ]
end
