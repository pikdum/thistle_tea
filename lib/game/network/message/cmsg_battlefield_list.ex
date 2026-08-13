defmodule ThistleTea.Game.Network.Message.CmsgBattlefieldList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEFIELD_LIST

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:map]

  @impl ClientMessage
  def handle(%__MODULE__{map: map}, state), do: Battlegrounds.list(state, map)

  @impl ClientMessage
  def from_binary(<<map::little-size(32)>>), do: %__MODULE__{map: map}
end
