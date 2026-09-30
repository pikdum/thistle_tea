defmodule ThistleTea.Game.Inbound.CmsgSetTradeGold do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SET_TRADE_GOLD

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct [:gold]

  @impl ClientMessage
  def from_binary(<<gold::little-size(32)>>), do: %__MODULE__{gold: gold}

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Trade.request(state, {:money, message.gold})
end
