defmodule ThistleTea.Game.Inbound.CmsgBattlefieldList do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BATTLEFIELD_LIST

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct [:map]

  @impl ClientMessage
  def from_binary(<<map::little-size(32)>>), do: %__MODULE__{map: map}

  @impl ClientMessage
  def handle(%__MODULE__{map: map}, state), do: Battlegrounds.list(state, map)
end
