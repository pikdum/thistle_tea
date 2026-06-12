defmodule ThistleTea.Game.Player.Items do
  @moduledoc """
  Grants items to a player session: creates the item instance, stores it in
  the inventory, and sends the push-result packet or chat feedback. Used by
  item-creating spells and the `.additem` dev command.
  """
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.ItemStore

  def give(state, item_id, count) do
    case ItemStore.create(item_id, owner: state.guid, stack_count: count) do
      %DataItem{} = item -> store_item(state, item, item_id, count)
      _ -> system_message(state, "Item #{item_id} not found.")
    end
  end

  defp store_item(state, item, item_id, count) do
    case Inventory.store(state.character.player, state.guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        {bag_slot, item_slot} = finish_placement(item, placement)
        state = InventoryUpdate.apply(state, {:ok, result})

        Network.send_packet(%Message.SmsgItemPushResult{
          player_guid: state.guid,
          item_id: item_id,
          bag_slot: bag_slot,
          item_slot: item_slot,
          count: count,
          created: 1
        })

        state

      _ ->
        ItemStore.delete(item.object.guid)
        system_message(state, "Inventory full.")
    end
  end

  defp finish_placement(_item, {:placed, {bag, slot}, placed}) do
    ItemStore.put(placed)
    Network.send_packet(UpdateObject.from_item(placed))
    {bag, slot}
  end

  defp finish_placement(item, :merged) do
    ItemStore.delete(item.object.guid)
    {Inventory.bag_0(), 0xFFFFFFFF}
  end

  defp system_message(state, message) do
    Network.send_packet(Message.SmsgMessagechat.system(message, state.guid))
    state
  end
end
