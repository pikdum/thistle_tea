defmodule ThistleTea.Game.World.Inbound.Vendor do
  @moduledoc "Handles decoded vendor, buyback, and repair client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Buyback
  alias ThistleTea.Game.World.Entity.Player.Durability
  alias ThistleTea.Game.World.Entity.Player.Vendor

  def messages do
    [
      Message.CmsgBuyItem,
      Message.CmsgBuyItemInSlot,
      Message.CmsgBuybackItem,
      Message.CmsgListInventory,
      Message.CmsgRepairItem,
      Message.CmsgSellItem
    ]
  end

  def handle(%Message.CmsgBuyItem{} = message, state) do
    Vendor.buy(state, message.vendor_guid, message.item_id, message.count)
  end

  def handle(%Message.CmsgBuyItemInSlot{} = message, state) do
    Vendor.buy_in_slot(state, message.vendor_guid, message.item_id, message.count, message.bag_guid, message.slot)
  end

  def handle(%Message.CmsgBuybackItem{} = message, state), do: Buyback.restore(state, message.vendor_guid, message.slot)

  def handle(%Message.CmsgListInventory{guid: guid}, state), do: Vendor.list(state, guid)

  def handle(%Message.CmsgRepairItem{vendor_guid: vendor_guid, item_guid: item_guid}, state) do
    Durability.repair(state, vendor_guid, item_guid)
  end

  def handle(%Message.CmsgSellItem{} = message, state) do
    Buyback.sell(state, message.vendor_guid, message.item_guid, message.count)
  end
end
