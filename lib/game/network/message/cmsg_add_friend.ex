defmodule ThistleTea.Game.Network.Message.CmsgAddFriend do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ADD_FRIEND

  alias ThistleTea.Game.Player.Social

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Social.add(state, :friend, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
