defmodule ThistleTea.Game.Network.Message.CmsgSetTradeItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_TRADE_ITEM

  defstruct [:trade_slot, :bag, :slot]

  @impl ClientMessage
  def from_binary(<<trade_slot, bag, slot>>), do: %__MODULE__{trade_slot: trade_slot, bag: bag, slot: slot}
end
