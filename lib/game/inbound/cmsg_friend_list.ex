defmodule ThistleTea.Game.Inbound.CmsgFriendList do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_FRIEND_LIST

  alias ThistleTea.Game.World.Entity.Player.Social

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Social.list(state)
end
