defmodule ThistleTea.Game.Network.Message.CmsgSplitItem do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SPLIT_ITEM

  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:src_bag, :src_slot, :dst_bag, :dst_slot, :count]

  @impl ClientMessage
  def handle(%__MODULE__{count: count} = message, %{ready: true, character: %Character{} = c} = state) when count > 0 do
    src_pos = {message.src_bag, message.src_slot}
    dst_pos = {message.dst_bag, message.dst_slot}
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- Inventory.item_guid_at(c.player, src_pos, get_item),
         %DataItem{} = src_item <- ItemStore.get(guid) do
      new_item = ItemStore.create(DataItem.template(src_item), owner: state.guid, stack_count: count)

      case Inventory.split(c.player, state.guid, src_pos, dst_pos, new_item, get_item) do
        {:ok, result, placed} ->
          ItemStore.put(placed)
          Network.send_packet(UpdateObject.from_item(placed))
          InventoryUpdate.apply(state, {:ok, result})

        {:error, error, item1_guid, item2_guid} ->
          ItemStore.delete(new_item.object.guid)
          InventoryUpdate.send_failure(error, item1_guid, item2_guid)
          state
      end
    else
      _ ->
        InventoryUpdate.send_failure(:item_not_found, 0, 0)
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<src_bag, src_slot, dst_bag, dst_slot, count>> = payload

    %__MODULE__{
      src_bag: src_bag,
      src_slot: src_slot,
      dst_bag: dst_bag,
      dst_slot: dst_slot,
      count: count
    }
  end
end
