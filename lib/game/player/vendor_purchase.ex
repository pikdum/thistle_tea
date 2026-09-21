defmodule ThistleTea.Game.Player.VendorPurchase do
  @moduledoc """
  Plans owner-local merchant inventory changes and projects committed stock
  receipts. Login recovers a purchase interrupted before owner acknowledgement.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Entity.Data.VendorStock.Receipt
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.System.VendorStock
  alias ThistleTea.Game.World.VendorStockStore

  def buy(state, vendor_guid, %VendorItem{} = item, count, price) do
    character = state.character
    purchase = %{character | player: %{character.player | coinage: character.player.coinage - price}}

    case Items.plan_store(purchase, item.template, count * max(item.template.buy_count, 1)) do
      {:ok, changes, position} ->
        receipt = %Receipt{
          id: make_ref(),
          guid: state.guid,
          changes: changes,
          old_counts: Quests.quest_item_counts(character),
          vendor_guid: vendor_guid,
          vendor_item: item,
          count: count,
          available: nil,
          position: position
        }

        CharacterStore.put(character)
        result = request(character.internal.world, receipt)

        case VendorStockStore.pending(state.guid) do
          %Receipt{} -> settle(state)
          nil -> failure(state, vendor_guid, item.template.entry, result)
        end

      {:error, _reason} ->
        failure(state, vendor_guid, item.template.entry, {:error, :cant_carry_more})
    end
  end

  def recover(%Character{} = character) do
    case VendorStockStore.pending(character.object.guid) do
      %Receipt{} = receipt -> character |> receipt_character(receipt) |> CharacterStore.put()
      nil -> character
    end
  end

  def finish_recovery(state) do
    case VendorStockStore.pending(state.guid) do
      %Receipt{} = receipt -> acknowledge(state, receipt)
      nil -> state
    end
  end

  def settle(state) do
    case VendorStockStore.pending(state.guid) do
      %Receipt{} = receipt ->
        state = project(state, receipt) |> acknowledge(receipt)
        success(receipt)
        state

      nil ->
        state
    end
  end

  defp request(world, receipt) do
    VendorStock.purchase(world, receipt)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp project(%{character: %{internal: %{last_vendor_purchase_id: id}}} = state, %Receipt{id: id}), do: state

  defp project(state, receipt) do
    character = receipt_character(state.character, receipt)
    InventoryUpdate.apply_committed(%{state | character: character}, receipt.changes, receipt.old_counts)
  end

  defp acknowledge(state, receipt) do
    state = Quests.on_inventory_changed(state, receipt.old_counts)
    CharacterStore.put(state.character)
    VendorStockStore.acknowledge(receipt)
    state
  end

  defp receipt_character(%Character{internal: %{last_vendor_purchase_id: id}} = character, %Receipt{id: id}),
    do: character

  defp receipt_character(%Character{} = character, receipt) do
    %{character | player: receipt.changes.player, internal: %{character.internal | last_vendor_purchase_id: receipt.id}}
  end

  defp success(receipt) do
    Network.send_packet(%Message.SmsgBuyItem{
      vendor_guid: receipt.vendor_guid,
      vendor_slot: receipt.vendor_item.index,
      new_count: receipt.available,
      count: receipt.count
    })

    {bag_slot, item_slot} = receipt.position

    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: receipt.guid,
      item_id: receipt.vendor_item.template.entry,
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: receipt.count * max(receipt.vendor_item.template.buy_count, 1),
      received: 1
    })
  end

  defp failure(state, vendor, item, {:error, reason}) do
    reason = if reason in [:item_already_sold, :cant_carry_more], do: reason, else: :cant_find_item
    Network.send_packet(%Message.SmsgBuyFailed{vendor_guid: vendor, item_id: item, error: reason})
    state
  end
end
