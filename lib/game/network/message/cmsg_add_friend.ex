defmodule ThistleTea.Game.Network.Message.CmsgAddFriend do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ADD_FRIEND

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
