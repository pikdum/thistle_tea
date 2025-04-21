defmodule ThistleTeaGame.ClientPacket do
  alias ThistleTeaGame.ClientPacket.CmsgAuthSession

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  # TODO: would be good to not have magic numbers
  @decoders %{
    0x1ED => CmsgAuthSession
  }

  def decode(%__MODULE__{opcode: opcode} = packet) do
    case Map.fetch(@decoders, opcode) do
      {:ok, mod} -> mod.decode(packet)
      :error -> {:error, :unknown_opcode, opcode}
    end
  end
end
