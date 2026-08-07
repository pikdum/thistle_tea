defmodule ThistleTea.Game.Player.Vendor do
  @moduledoc """
  Owns condition-aware vendor listing and purchase authorization.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

  def list(%{ready: true, character: %Character{} = character} = state, vendor_guid) do
    if !Core.dead?(character) and Reputation.can_interact?(character, vendor_guid) do
      Network.send_packet(%Message.SmsgListInventory{
        vendor_guid: vendor_guid,
        items: visible_items(character, vendor_guid)
      })
    end

    state
  end

  def list(state, _vendor_guid), do: state

  def buy(%{ready: true, character: %Character{} = character} = state, vendor_guid, item_id, requested_count) do
    count = max(requested_count, 1)

    case Enum.find(visible_items(character, vendor_guid), &(&1.template.entry == item_id)) do
      %{template: template} = vendor_item ->
        buy_visible(state, character, vendor_guid, vendor_item, template, count)

      _missing_or_condition_failed ->
        send_buy_failed(vendor_guid, item_id, :cant_find_item)
        state
    end
  end

  def buy(state, _vendor_guid, _item_id, _count), do: state

  def visible_items(%Character{} = character, vendor_guid) do
    items = VendorLoader.items(Guid.entry(vendor_guid))
    conditions = Enum.map(items, &condition_of/1)

    visible = condition_visible_items(character, vendor_guid, items, conditions)
    Reputation.vendor_items(character, vendor_guid, visible)
  end

  defp condition_of(%{} = item), do: Map.get(item, :condition)

  defp condition_visible_items(character, vendor_guid, items, conditions) do
    if Enum.all?(conditions, &is_nil/1) do
      items
    else
      context = condition_context(character, vendor_guid, conditions)
      Enum.filter(items, &(Condition.evaluate(context, condition_of(&1)) == :met))
    end
  end

  defp condition_context(character, vendor_guid, conditions) do
    source = %Subject{guid: vendor_guid, kind: :mob, entry: Guid.entry(vendor_guid), alive?: true}
    ConditionContext.build(character, conditions, source: source)
  end

  defp buy_visible(state, character, vendor_guid, vendor_item, template, count) do
    price = Reputation.price(character, vendor_guid, template.buy_price * count)
    total_count = max(template.buy_count, 1) * count

    cond do
      not Reputation.can_interact?(character, vendor_guid) ->
        state

      not Reputation.item_requirement_met?(character, vendor_guid, template) ->
        send_buy_failed(vendor_guid, template.entry, :reputation_require)
        state

      character.player.coinage < price ->
        send_buy_failed(vendor_guid, template.entry, :not_enough_money)
        state

      not Inventory.can_store?(character.player, template, total_count, &ItemStore.get/1) ->
        send_buy_failed(vendor_guid, template.entry, :cant_carry_more)
        state

      true ->
        complete_purchase(state, character, vendor_guid, vendor_item, template, total_count, price)
    end
  end

  defp complete_purchase(state, character, vendor_guid, vendor_item, template, total_count, price) do
    item = ItemStore.create(template, owner: state.guid, stack_count: total_count)

    case Inventory.store(character.player, state.guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        {bag_slot, item_slot} = InventoryUpdate.commit_placement(item, placement)
        player = %{result.player | coinage: character.player.coinage - price}
        state = InventoryUpdate.apply(state, {:ok, %{result | player: player}}, placement)

        Network.send_packet(%Message.SmsgBuyItem{
          vendor_guid: vendor_guid,
          vendor_slot: vendor_item.index,
          count: total_count
        })

        Network.send_packet(%Message.SmsgItemPushResult{
          player_guid: state.guid,
          item_id: template.entry,
          bag_slot: bag_slot,
          item_slot: item_slot,
          count: total_count,
          received: 1
        })

        state

      _error ->
        ItemStore.delete(item.object.guid)
        send_buy_failed(vendor_guid, template.entry, :cant_carry_more)
        state
    end
  end

  defp send_buy_failed(vendor_guid, item_id, error) do
    Network.send_packet(%Message.SmsgBuyFailed{
      vendor_guid: vendor_guid,
      item_id: item_id,
      error: error
    })
  end
end
