defmodule ThistleTea.Game.Inbound.CmsgSellItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SELL_ITEM

  alias ThistleTea.Game.World.Entity.Player.Buyback

  defstruct [:vendor_guid, :item_guid, :count]

  @impl ClientMessage
  def from_binary(<<vendor::little-size(64), item::little-size(64), count>>) do
    %__MODULE__{vendor_guid: vendor, item_guid: item, count: count}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Buyback.sell(state, message.vendor_guid, message.item_guid, message.count)
  end
end
