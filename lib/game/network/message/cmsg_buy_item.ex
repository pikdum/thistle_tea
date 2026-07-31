defmodule ThistleTea.Game.Network.Message.CmsgBuyItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_ITEM

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

  defstruct [:vendor_guid, :item_id, :count]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{} = c} = state) do
    count = max(message.count, 1)

    case VendorLoader.find_item(Guid.entry(message.vendor_guid), message.item_id) do
      %{template: template} = vendor_item ->
        buy(state, c, message, vendor_item, template, count)

      _ ->
        send_buy_failed(message, :cant_find_item)
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<vendor_guid::little-size(64), item_id::little-size(32), count, _unk>> = payload

    %__MODULE__{
      vendor_guid: vendor_guid,
      item_id: item_id,
      count: count
    }
  end

  defp buy(state, c, message, vendor_item, template, count) do
    price = PlayerReputation.price(c, message.vendor_guid, template.buy_price * count)
    total_count = max(template.buy_count, 1) * count
    coinage = c.player.coinage

    cond do
      not PlayerReputation.can_interact?(c, message.vendor_guid) ->
        state

      not PlayerReputation.item_requirement_met?(c, message.vendor_guid, template) ->
        send_buy_failed(message, :reputation_require)
        state

      coinage < price ->
        send_buy_failed(message, :not_enough_money)
        state

      not Inventory.can_store?(c.player, template, total_count, &ItemStore.get/1) ->
        send_buy_failed(message, :cant_carry_more)
        state

      true ->
        complete_purchase(state, c, message, vendor_item, template, total_count, price)
    end
  end

  defp complete_purchase(state, c, message, vendor_item, template, total_count, price) do
    item = ItemStore.create(template, owner: state.guid, stack_count: total_count)

    case Inventory.store(c.player, state.guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        {bag_slot, item_slot} = InventoryUpdate.commit_placement(item, placement)
        player = %{result.player | coinage: c.player.coinage - price}
        state = InventoryUpdate.apply(state, {:ok, %{result | player: player}}, placement)

        Network.send_packet(%Message.SmsgBuyItem{
          vendor_guid: message.vendor_guid,
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

      _ ->
        ItemStore.delete(item.object.guid)
        send_buy_failed(message, :cant_carry_more)
        state
    end
  end

  defp send_buy_failed(%__MODULE__{vendor_guid: vendor_guid, item_id: item_id}, error) do
    Network.send_packet(%Message.SmsgBuyFailed{
      vendor_guid: vendor_guid,
      item_id: item_id,
      error: error
    })
  end
end
