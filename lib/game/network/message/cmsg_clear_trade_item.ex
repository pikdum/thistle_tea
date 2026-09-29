defmodule ThistleTea.Game.Network.Message.CmsgClearTradeItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CLEAR_TRADE_ITEM

  defstruct [:trade_slot]

  @impl ClientMessage
  def from_binary(<<trade_slot>>), do: %__MODULE__{trade_slot: trade_slot}
end
