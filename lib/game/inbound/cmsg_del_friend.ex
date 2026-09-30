defmodule ThistleTea.Game.Inbound.CmsgDelFriend do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_DEL_FRIEND

  alias ThistleTea.Game.World.Entity.Player.Social

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Social.remove(state, :friend, guid)
end
