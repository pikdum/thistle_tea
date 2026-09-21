defmodule ThistleTea.Game.Network.Message.CmsgFriendList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FRIEND_LIST

  alias ThistleTea.Game.Player.Social

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Social.list(state)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
