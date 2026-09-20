defmodule ThistleTea.Game.Network.Message.CmsgAcceptTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ACCEPT_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct [:unknown]

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, :accept)

  @impl ClientMessage
  def from_binary(<<unknown::little-size(32)>>), do: %__MODULE__{unknown: unknown}
end
