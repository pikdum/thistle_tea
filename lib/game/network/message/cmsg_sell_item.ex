defmodule ThistleTea.Game.Network.Message.CmsgSellItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SELL_ITEM

  alias ThistleTea.Game.Player.Buyback

  defstruct [:vendor_guid, :item_guid, :count]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Buyback.sell(state, message.vendor_guid, message.item_guid, message.count)
  end

  @impl ClientMessage
  def from_binary(<<vendor::little-size(64), item::little-size(64), count>>) do
    %__MODULE__{vendor_guid: vendor, item_guid: item, count: count}
  end
end
