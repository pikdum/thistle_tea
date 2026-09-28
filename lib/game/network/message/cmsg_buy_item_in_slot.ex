defmodule ThistleTea.Game.Network.Message.CmsgBuyItemInSlot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_ITEM_IN_SLOT

  alias ThistleTea.Game.Player.Vendor

  defstruct [:vendor_guid, :item_id, :bag_guid, :slot, :count]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Vendor.buy_in_slot(state, message.vendor_guid, message.item_id, message.count, message.bag_guid, message.slot)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<vendor::little-size(64), item::little-size(32), bag::little-size(64), slot, count>> = payload
    %__MODULE__{vendor_guid: vendor, item_id: item, bag_guid: bag, slot: slot, count: count}
  end
end
