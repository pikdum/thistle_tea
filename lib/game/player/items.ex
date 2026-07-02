defmodule ThistleTea.Game.Player.Items do
  @moduledoc """
  Grants and consumes items for a player session: creates or removes the item
  instance, updates the inventory, and sends the client packets. Used by
  item-creating spells, consumable on-use items, and the `.additem` dev
  command.
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

  def consume(state, item_guid) when is_integer(item_guid) do
    with %DataItem{} = item <- ItemStore.get(item_guid),
         {_bag, _slot} = pos <- Inventory.find_position(state.character.player, item_guid, &ItemStore.get/1) do
      consume_at(state, item, pos)
    else
      _ -> state
    end
  end

  def consume(state, _item_guid), do: state

  defp consume_at(state, %DataItem{} = item, pos) do
    get_item = &ItemStore.get/1

    if (item.item.stack_count || 1) > 1 do
      case Inventory.reduce_stack(state.character.player, pos, 1, get_item) do
        {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
        _ -> state
      end
    else
      case Inventory.destroy(state.character.player, pos, get_item) do
        {:ok, result, _item} ->
          ItemStore.delete(item.object.guid)
          Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
          InventoryUpdate.apply(state, {:ok, result})

        _ ->
          state
      end
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
