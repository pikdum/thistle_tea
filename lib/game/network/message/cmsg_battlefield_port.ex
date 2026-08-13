defmodule ThistleTea.Game.Network.Message.CmsgBattlefieldPort do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEFIELD_PORT

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:map, :action]

  @impl ClientMessage
  def handle(%__MODULE__{action: action}, state), do: Battlegrounds.port(state, action)

  @impl ClientMessage
  def from_binary(<<map::little-size(32), action::little-size(8)>>), do: %__MODULE__{map: map, action: action}
end
