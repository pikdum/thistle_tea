defmodule ThistleTea.Game.World.Inbound.Item do
  @moduledoc "Handles decoded inventory, bank, and item use client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Inventory, as: InventoryLogic
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Ammunition
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.Containers
  alias ThistleTea.Game.World.Entity.Player.Gifts
  alias ThistleTea.Game.World.Entity.Player.Inventory
  alias ThistleTea.Game.World.Entity.Player.UsableItems

  def messages do
    [
      Message.CmsgAutobankItem,
      Message.CmsgAutoequipItem,
      Message.CmsgAutoequipItemSlot,
      Message.CmsgAutostoreBagItem,
      Message.CmsgAutostoreBankItem,
      Message.CmsgBuyBankSlot,
      Message.CmsgDestroyitem,
      Message.CmsgOpenItem,
      Message.CmsgReadItem,
      Message.CmsgSetAmmo,
      Message.CmsgSplitItem,
      Message.CmsgSwapInvItem,
      Message.CmsgSwapItem,
      Message.CmsgUseItem,
      Message.CmsgWrapItem
    ]
  end

  def handle(%Message.CmsgAutobankItem{source_bag: bag, source_slot: slot}, state),
    do: Bank.auto_bank(state, {bag, slot})

  def handle(
        %Message.CmsgAutoequipItem{src_bag: src_bag, src_slot: src_slot},
        %{ready: true, character: %Character{}} = state
      ) do
    Inventory.auto_equip(state, {src_bag, src_slot})
  end

  def handle(%Message.CmsgAutoequipItem{}, state), do: state

  def handle(
        %Message.CmsgAutoequipItemSlot{item_guid: guid, destination_slot: slot},
        %{ready: true, character: %Character{}} = state
      ) do
    Inventory.equip_item(state, guid, slot)
  end

  def handle(%Message.CmsgAutoequipItemSlot{}, state), do: state

  def handle(%Message.CmsgAutostoreBagItem{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.auto_store_in_bag(state, {message.source_bag, message.source_slot}, message.destination_bag)
  end

  def handle(%Message.CmsgAutostoreBagItem{}, state), do: state

  def handle(%Message.CmsgAutostoreBankItem{source_bag: bag, source_slot: slot}, state),
    do: Bank.auto_store_bank(state, {bag, slot})

  def handle(%Message.CmsgBuyBankSlot{banker_guid: banker_guid}, state), do: Bank.buy_slot(state, banker_guid)

  def handle(%Message.CmsgDestroyitem{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.destroy(state, {bag, slot})
  end

  def handle(%Message.CmsgDestroyitem{}, state), do: state

  def handle(%Message.CmsgOpenItem{bag: bag, slot: slot}, %{ready: true} = state),
    do: Containers.open(state, {bag, slot})

  def handle(%Message.CmsgOpenItem{}, state), do: state

  def handle(%Message.CmsgReadItem{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state),
    do: UsableItems.read(state, {bag, slot})

  def handle(%Message.CmsgReadItem{}, state), do: state

  def handle(%Message.CmsgSetAmmo{item: item}, %{ready: true, character: %Character{}} = state),
    do: Ammunition.select(state, item)

  def handle(%Message.CmsgSetAmmo{}, state), do: state

  def handle(%Message.CmsgSplitItem{count: count} = message, %{ready: true, character: %Character{}} = state)
      when count > 0 do
    src_pos = {message.src_bag, message.src_slot}
    dst_pos = {message.dst_bag, message.dst_slot}
    Inventory.split(state, src_pos, dst_pos, count)
  end

  def handle(%Message.CmsgSplitItem{}, state), do: state

  def handle(
        %Message.CmsgSwapInvItem{src_slot: src_slot, dst_slot: dst_slot},
        %{ready: true, character: %Character{}} = state
      ) do
    bag_0 = InventoryLogic.bag_0()
    Inventory.swap(state, {bag_0, src_slot}, {bag_0, dst_slot})
  end

  def handle(%Message.CmsgSwapInvItem{}, state), do: state

  def handle(%Message.CmsgSwapItem{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.swap(state, {message.src_bag, message.src_slot}, {message.dst_bag, message.dst_slot})
  end

  def handle(%Message.CmsgSwapItem{}, state), do: state

  def handle(%Message.CmsgUseItem{} = message, %{ready: true, character: %Character{}} = state),
    do: UsableItems.use(state, {message.bag, message.slot}, message.targets)

  def handle(%Message.CmsgUseItem{}, state), do: state

  def handle(%Message.CmsgWrapItem{} = message, state) do
    Gifts.wrap(state, {message.gift_bag, message.gift_slot}, {message.item_bag, message.item_slot})
  end
end
