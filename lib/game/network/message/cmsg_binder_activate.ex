defmodule ThistleTea.Game.Network.Message.CmsgBinderActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BINDER_ACTIVATE

  alias ThistleTea.Game.Player.HomeBind

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: HomeBind.activate(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
