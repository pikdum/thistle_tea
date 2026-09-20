defmodule ThistleTea.Game.Network.Message.CmsgSetTradeGold do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_TRADE_GOLD

  alias ThistleTea.Game.Player.Trade

  defstruct [:gold]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Trade.request(state, {:money, message.gold})

  @impl ClientMessage
  def from_binary(<<gold::little-size(32)>>), do: %__MODULE__{gold: gold}
end
