defmodule ThistleTea.Game.Player.ItemLoot do
  @moduledoc """
  Projects and claims player-owned item loot. Closing the window stores
  remaining materials when possible; failed claims remain on the character
  and reopen on login or the next Disenchant attempt.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.ItemLoot, as: PendingLoot
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World.ItemStore

  def open(%{character: %Character{internal: %{item_loot: %PendingLoot{} = pending}} = character} = state) do
    if Core.dead?(character) do
      state
    else
      Network.send_packet(%Message.SmsgLootResponse{guid: pending.guid, loot: pending.loot, loot_type: 2})
      %{state | loot_guid: pending.guid, loot_type: :item}
    end
  end

  def open(state), do: state

  def take_item(
        %{loot_guid: guid, character: %Character{internal: %{item_loot: %PendingLoot{guid: guid}}}} = state,
        slot
      ) do
    if Core.dead?(state.character), do: state, else: claim(state, slot)
  end

  def take_item(state, _slot), do: state

  def release(%{character: %Character{internal: %{item_loot: %PendingLoot{loot: loot}}}} = state) do
    Enum.reduce(loot.items, state, fn
      %Loot.Item{looted: false, slot: slot}, state -> take_item(state, slot)
      _item, state -> state
    end)
  end

  def release(state), do: state

  defp claim(state, slot) do
    pending = state.character.internal.item_loot

    with %Loot.Item{} = reward <- Enum.find(pending.loot.items, &(&1.slot == slot and not &1.looted)),
         %Item{} = item <- ItemStore.prepare(reward.item_id, owner: state.guid, stack_count: reward.count),
         {:ok, character, changes} <- PendingLoot.claim(state.character, slot, item, &ItemStore.get/1) do
      state = InventoryUpdate.apply(%{state | character: character}, {:ok, changes})
      Network.send_packet(%Message.SmsgLootRemoved{slot: slot})
      Items.send_push_result(state, reward.item_id, reward.count, position(changes, item.object.guid))
      state
    else
      {:error, reason} -> failure(state, reason)
      _ -> failure(state, :already_looted)
    end
  end

  defp position(changes, guid) do
    case ChangeSet.placement(changes, guid) do
      %Placement{status: :placed, position: position} -> position
      %Placement{status: :merged} -> {Inventory.bag_0(), 0xFFFFFFFF}
    end
  end

  defp failure(state, reason) do
    InventoryUpdate.send_failure(reason, 0, 0)
    state
  end
end
