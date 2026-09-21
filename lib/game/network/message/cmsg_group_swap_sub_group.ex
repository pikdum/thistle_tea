defmodule ThistleTea.Game.Network.Message.CmsgGroupSwapSubGroup do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_SWAP_SUB_GROUP

  alias ThistleTea.Game.Player.Groups

  defstruct [:first, :second]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, first, rest} = BinaryUtils.parse_string(payload)
    {:ok, second, <<>>} = BinaryUtils.parse_string(rest)
    %__MODULE__{first: first, second: second}
  end

  @impl ClientMessage
  def handle(%__MODULE__{first: first, second: second}, state), do: Groups.swap_subgroups(state, first, second)
end
