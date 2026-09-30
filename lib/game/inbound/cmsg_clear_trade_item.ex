defmodule ThistleTea.Game.Inbound.CmsgClearTradeItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CLEAR_TRADE_ITEM

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct [:trade_slot]

  @impl ClientMessage
  def from_binary(<<trade_slot>>), do: %__MODULE__{trade_slot: trade_slot}

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Trade.request(state, {:clear, message.trade_slot})
end
