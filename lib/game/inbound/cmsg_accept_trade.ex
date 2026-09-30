defmodule ThistleTea.Game.Inbound.CmsgAcceptTrade do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ACCEPT_TRADE

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct [:unknown]

  @impl ClientMessage
  def from_binary(<<unknown::little-size(32)>>), do: %__MODULE__{unknown: unknown}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, :accept)
end
