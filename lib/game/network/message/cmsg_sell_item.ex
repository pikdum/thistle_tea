defmodule ThistleTea.Game.Network.Message.CmsgSellItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SELL_ITEM

  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:vendor_guid, :item_guid, :count]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{} = c} = state) do
    get_item = &ItemStore.get/1

    with pos when pos != nil <- Inventory.find_position(c.player, message.item_guid, get_item),
         %DataItem{} = item <- ItemStore.get(message.item_guid) do
      sell(state, c, message, pos, item)
    else
      _ ->
        send_sell_error(message, :cant_find_item)
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<vendor_guid::little-size(64), item_guid::little-size(64), count>> = payload

    %__MODULE__{
      vendor_guid: vendor_guid,
      item_guid: item_guid,
      count: count
    }
  end

  defp sell(state, c, message, pos, item) do
    template = DataItem.template(item)
    stack_count = item.item.stack_count || 1
    count = if message.count == 0 or message.count >= stack_count, do: stack_count, else: message.count

    if template.sell_price > 0 do
      complete_sale(state, c, message, pos, item, count, stack_count, template.sell_price)
    else
      send_sell_error(message, :cant_sell_item)
      state
    end
  end

  defp complete_sale(state, c, message, pos, item, count, stack_count, sell_price) do
    get_item = &ItemStore.get/1

    result =
      if count == stack_count do
        case Inventory.destroy(c.player, pos, get_item) do
          {:ok, result, _item} ->
            ItemStore.delete(item.object.guid)
            Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
            {:ok, result}

          {:error, :can_only_do_with_empty_bags, _, _} ->
            {:sell_error, :only_empty_bag}

          {:error, _, _, _} ->
            {:sell_error, :cant_sell_item}
        end
      else
        case Inventory.reduce_stack(c.player, pos, count, get_item) do
          {:ok, result} -> {:ok, result}
          _ -> {:sell_error, :cant_find_item}
        end
      end

    case result do
      {:ok, result} ->
        player = %{result.player | coinage: c.player.coinage + sell_price * count}
        InventoryUpdate.apply(state, {:ok, %{result | player: player}})

      {:sell_error, error} ->
        send_sell_error(message, error)
        state
    end
  end

  defp send_sell_error(%__MODULE__{vendor_guid: vendor_guid, item_guid: item_guid}, error) do
    Network.send_packet(%Message.SmsgSellItem{
      vendor_guid: vendor_guid,
      item_guid: item_guid,
      error: error
    })
  end
end
