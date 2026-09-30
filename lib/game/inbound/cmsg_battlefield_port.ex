defmodule ThistleTea.Game.Inbound.CmsgBattlefieldPort do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BATTLEFIELD_PORT

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct [:map, :action]

  @impl ClientMessage
  def from_binary(<<map::little-size(32), action::little-size(8)>>), do: %__MODULE__{map: map, action: action}

  @impl ClientMessage
  def handle(%__MODULE__{action: action}, state), do: Battlegrounds.port(state, action)
end
