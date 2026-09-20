defmodule ThistleTea.Game.Network.Message.CmsgSetTradeItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_TRADE_ITEM

  alias ThistleTea.Game.Player.Trade

  defstruct [:trade_slot, :bag, :slot]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state),
    do: Trade.request(state, {:item, message.trade_slot, message.bag, message.slot})

  @impl ClientMessage
  def from_binary(<<trade_slot, bag, slot>>), do: %__MODULE__{trade_slot: trade_slot, bag: bag, slot: slot}
end
