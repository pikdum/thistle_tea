defmodule ThistleTea.Game.Network.Message.CmsgFriendList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FRIEND_LIST

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
