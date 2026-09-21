defmodule ThistleTea.Game.Network.Message.CmsgDelIgnore do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DEL_IGNORE

  alias ThistleTea.Game.Player.Social

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Social.remove(state, :ignore, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{guid: guid}
end
