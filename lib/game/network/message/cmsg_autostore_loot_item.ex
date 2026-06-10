defmodule ThistleTea.Game.Network.Message.CmsgAutostoreLootItem do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:slot]

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, %{ready: true, character: %Character{} = c, loot_guid: loot_guid} = state)
      when is_integer(loot_guid) do
    if Inventory.free_backpack_slot(c.player) == nil do
      InventoryUpdate.send_failure(:inventory_full, 0, 0)
      state
    else
      case Entity.call(loot_guid, {:loot_take_item, slot}) do
        {:ok, %Loot.Item{} = loot_item} ->
          store_loot_item(state, loot_item, slot)

        _ ->
          InventoryUpdate.send_failure(:already_looted, 0, 0)
          state
      end
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

    case item && Inventory.store(c.player, item) do
      {:ok, player, dst_slot} ->
        Network.send_packet(UpdateObject.from_item(item))
        state = InventoryUpdate.apply(state, {:ok, player})
        Network.send_packet(%Message.SmsgLootRemoved{slot: loot_slot})

        Network.send_packet(%Message.SmsgItemPushResult{
          player_guid: state.guid,
          item_id: loot_item.item_id,
          bag_slot: Inventory.bag_0(),
          item_slot: dst_slot,
          count: loot_item.count
        })

        state

      _ ->
        if item, do: ItemStore.delete(item.object.guid)
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state
    end
  end
end
