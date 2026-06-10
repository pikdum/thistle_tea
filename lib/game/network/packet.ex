defmodule ThistleTea.Game.Network.Packet do
  defstruct [
    :opcode,
    :size,
    :payload
  ]

  def build(payload, opcode) when is_number(opcode) and is_binary(payload) do
    %__MODULE__{
      opcode: opcode,
      size: byte_size(payload) + 2,
      payload: payload
    }
  end
end
