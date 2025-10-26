defmodule ThistleTea.Game.Packet do
  alias ThistleTea.Game.Message.CmsgAuthSession

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  @l %{
       CMSG_AUTH_SESSION: CmsgAuthSession
     }
     |> Map.new(fn {k, v} -> {ThistleTea.Opcodes.get(k), v} end)

  def build(payload, opcode) when is_number(opcode) and is_binary(payload) do
    %__MODULE__{
      opcode: opcode,
      size: byte_size(payload) + 2,
      payload: payload
    }
  end

  def to_message(%__MODULE__{opcode: opcode, payload: payload}) do
    module = Map.fetch!(@l, opcode)
    module.from_binary(payload)
  end

  def implemented?(opcode) when is_number(opcode) do
    Map.has_key?(@l, opcode)
  end
end
