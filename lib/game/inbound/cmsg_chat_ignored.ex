defmodule ThistleTea.Game.Inbound.CmsgChatIgnored do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHAT_IGNORED

  alias ThistleTea.Game.World.Entity.Player.Social

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Social.ignored(state, guid)
end
