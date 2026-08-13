defmodule ThistleTea.Game.Network.Message.CmsgLeaveBattlefield do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEAVE_BATTLEFIELD

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:map]

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.leave(state)

  @impl ClientMessage
  def from_binary(<<map::little-size(32)>>), do: %__MODULE__{map: map}
end
