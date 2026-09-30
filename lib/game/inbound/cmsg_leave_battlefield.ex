defmodule ThistleTea.Game.Inbound.CmsgLeaveBattlefield do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LEAVE_BATTLEFIELD

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct [:map]

  @impl ClientMessage
  def from_binary(<<map::little-size(32)>>), do: %__MODULE__{map: map}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.leave(state)
end
