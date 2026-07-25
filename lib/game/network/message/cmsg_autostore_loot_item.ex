defmodule ThistleTea.Game.Network.Message.CmsgAutostoreLootItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.World.ItemStore

  defstruct [:slot]

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, %{ready: true, character: %Character{}, loot_guid: loot_guid} = state)
      when is_integer(loot_guid) do
    actor = Looting.actor(state, loot_guid)

    case Entity.call(loot_guid, {:loot_take_item, actor, slot}) do
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
        placed_at = InventoryUpdate.commit_placement(item, placement)
        state = InventoryUpdate.apply(state, {:ok, result}, placement)
        Network.send_packet(%Message.SmsgLootRemoved{slot: loot_slot})
        send_push_result(state, loot_item.item_id, loot_item.count, placed_at)
        state

      _ ->
        if item, do: ItemStore.delete(item.object.guid)
        Entity.call(state.loot_guid, {:loot_return_item, loot_slot})
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state
    end
  end

  defp send_push_result(state, item_id, count, {bag_slot, item_slot}) do
    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: state.guid,
      item_id: item_id,
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: count
    })
  end
end
