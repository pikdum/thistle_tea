defmodule ThistleTea.Game.Network.Message.CmsgGroupSwapSubGroup do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_SWAP_SUB_GROUP

  defstruct [:first, :second]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, first, rest} = BinaryUtils.parse_string(payload)
    {:ok, second, <<>>} = BinaryUtils.parse_string(rest)
    %__MODULE__{first: first, second: second}
  end
end
