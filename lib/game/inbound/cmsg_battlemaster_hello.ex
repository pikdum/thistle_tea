defmodule ThistleTea.Game.Inbound.CmsgBattlemasterHello do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BATTLEMASTER_HELLO

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Battlegrounds.battlemaster_hello(state, guid)
end
