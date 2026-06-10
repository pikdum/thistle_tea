defmodule ThistleTea.Game.Network.Message.CmsgAutostoreLootItem do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:slot]

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, %{ready: true, character: %Character{}, loot_guid: loot_guid} = state)
      when is_integer(loot_guid) do
    case Entity.call(loot_guid, {:loot_take_item, slot}) do
      {:ok, %Loot.Item{} = loot_item} ->
        store_loot_item(state, loot_item, slot)

      _ ->
        InventoryUpdate.send_failure(:already_looted, 0, 0)
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<slot>> = payload

    %__MODULE__{
      slot: slot
    }
  end

  defp store_loot_item(%{character: c} = state, %Loot.Item{} = loot_item, loot_slot) do
    item = ItemStore.create(loot_item.item_id, owner: state.guid, stack_count: loot_item.count)

    case item && Inventory.store(c.player, state.guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        finish_placement(item, placement)
        state = InventoryUpdate.apply(state, {:ok, result})
        Network.send_packet(%Message.SmsgLootRemoved{slot: loot_slot})
        send_push_result(state, loot_item.item_id, loot_item.count, placement)
        state

      _ ->
        if item, do: ItemStore.delete(item.object.guid)
        Entity.call(state.loot_guid, {:loot_return_item, loot_slot})
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state
    end
  end

  defp finish_placement(_item, {:placed, _pos, placed}) do
    ItemStore.put(placed)
    Network.send_packet(UpdateObject.from_item(placed))
  end

  defp finish_placement(item, :merged) do
    ItemStore.delete(item.object.guid)
  end

  defp send_push_result(state, item_id, count, placement) do
    {bag_slot, item_slot} =
      case placement do
        {:placed, {bag, slot}, _placed} -> {bag, slot}
        :merged -> {Inventory.bag_0(), 0xFFFFFFFF}
      end

    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: state.guid,
      item_id: item_id,
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: count
    })
  end
end
