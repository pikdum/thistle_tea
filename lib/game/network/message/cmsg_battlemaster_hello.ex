defmodule ThistleTea.Game.Network.Message.CmsgBattlemasterHello do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEMASTER_HELLO

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Battlegrounds.battlemaster_hello(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
