defmodule ThistleTea.Game.Player.Buyback do
  @moduledoc """
  Owner-local sales and buyback. Revalidates live vendors and settles pending
  item costs before committing the complete inventory and money transaction.
  """

  alias ThistleTea.Game.Entity.Data.Buyback.Change
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Buyback, as: BuybackLogic
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.Player.ItemDurations
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Durability, as: DurabilityLoader

  def sell(%State{ready: true, active_mover_guid: mover, guid: guid} = state, vendor, item_guid, count)
      when mover in [nil, 0, guid] do
    if Vendor.valid_vendor?(state.character, vendor) do
      state = state |> ItemCosts.settle() |> ItemDurations.expire_due()
      sell_authorized(state, vendor, item_guid, count)
    else
      sell_error(state, vendor, item_guid, :cant_find_vendor)
    end
  end

  def sell(state, _vendor, _item, _count), do: state

  def restore(%State{ready: true, active_mover_guid: mover, guid: guid} = state, vendor, slot)
      when mover in [nil, 0, guid] do
    if Vendor.valid_vendor?(state.character, vendor) do
      restore_authorized(ItemCosts.settle(state), vendor, slot)
    else
      sell_error(state, vendor, 0, :cant_find_vendor)
    end
  end

  def restore(state, _vendor, _slot), do: state

  def reset(%Character{} = character, now \\ Time.now()) do
    change = BuybackLogic.clear(character, now, &ItemStore.get/1)
    Enum.each(ChangeSet.destroyed_items(change.inventory), &ItemStore.delete(&1.object.guid))
    %{character | player: change.inventory.player, internal: %{character.internal | buyback: change.buyback}}
  end

  def logout(%State{character: %Character{} = character} = state) do
    case BuybackLogic.clear(character, Time.now(), &ItemStore.get/1) do
      %Change{inventory: %{destroyed: destroyed}} = change when map_size(destroyed) > 0 ->
        commit(state, change)

      %Change{} = change ->
        %{
          state
          | character: %{
              character
              | player: change.inventory.player,
                internal: %{character.internal | buyback: change.buyback}
            }
        }
    end
  end

  def logout(state), do: state

  defp sell_authorized(%State{loot_guid: item_guid} = state, vendor, item_guid, _count),
    do: sell_error(state, vendor, item_guid, :cant_sell_item)

  defp sell_authorized(state, vendor, item_guid, count) do
    new_guid =
      case ItemStore.get(item_guid) do
        %Item{} = item when count > 0 and count < item.item.stack_count ->
          ItemStore.prepare(Item.template(item)).object.guid

        _ ->
          item_guid
      end

    case BuybackLogic.sell(
           state.character,
           item_guid,
           count,
           new_guid,
           Time.now(),
           &ItemStore.get/1,
           &DurabilityLoader.sale_penalty/1
         ) do
      {:ok, change} -> state |> cancel_sold_cast(change) |> commit(change)
      {:error, reason} -> sell_error(state, vendor, item_guid, reason)
    end
  end

  defp restore_authorized(state, vendor, slot) do
    case BuybackLogic.restore(state.character, slot, Time.now(), &ItemStore.get/1) do
      {:ok, change} ->
        state = commit(state, change)
        Enum.each(ChangeSet.placed_items(change.inventory), &Enchantments.schedule_item_expiry/1)
        Enchantments.send_active_timers(state.character)
        state

      {:error, reason} when reason in [:cant_find_item, :not_enough_money] ->
        Network.send_packet(%Message.SmsgBuyFailed{vendor_guid: vendor, item_id: entry_id(state, slot), error: reason})
        state

      {:error, reason} ->
        InventoryUpdate.send_failure(reason, 0, 0)
        state
    end
  end

  defp entry_id(state, slot) do
    with %{guid: guid} <- Map.get(state.character.internal.buyback.entries, slot),
         %Item{} = item <- ItemStore.get(guid),
         do: item.object.entry,
         else: (_ -> 0)
  end

  defp commit(state, %Change{} = change) do
    character = %{state.character | internal: %{state.character.internal | buyback: change.buyback}}
    InventoryUpdate.apply(%{state | character: character}, {:ok, change.inventory})
  end

  defp cancel_sold_cast(%State{character: %{internal: %{casting: %Cast{cast_item_guid: guid}}}} = state, %Change{
         sold_guid: guid,
         removed_from_inventory?: true
       }), do: Spellcasting.cancel(state)

  defp cancel_sold_cast(state, _change), do: state

  defp sell_error(state, vendor, item, error) do
    Network.send_packet(%Message.SmsgSellItem{vendor_guid: vendor, item_guid: item, error: error})
    state
  end
end
