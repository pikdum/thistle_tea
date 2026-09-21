defmodule ThistleTea.Game.Player.Vendor do
  @moduledoc """
  Owns condition-aware vendor listing, live vendor authorization, and purchases.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Honor.ItemRequirements
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata

  def list(%{ready: true, character: %Character{} = character} = state, vendor_guid) do
    if valid_vendor?(character, vendor_guid) do
      Network.send_packet(%Message.SmsgListInventory{
        vendor_guid: vendor_guid,
        items: visible_items(character, vendor_guid)
      })
    end

    state
  end

  def list(state, _vendor_guid), do: state

  def buy(%{ready: true, character: %Character{} = character} = state, vendor_guid, item_id, requested_count) do
    if valid_vendor?(character, vendor_guid) do
      buy_authorized(state, character, vendor_guid, item_id, max(requested_count, 1))
    else
      send_buy_failed(vendor_guid, item_id, :distance_too_far)
      state
    end
  end

  def buy(state, _vendor_guid, _item_id, _count), do: state

  def valid_vendor?(%Character{} = character, vendor_guid) do
    with true <- Death.alive?(character),
         :mob <- Guid.entity_type(vendor_guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(vendor_guid, [:alive?, :npc_flags]),
         true <- (flags &&& 0x80) != 0,
         true <- Reputation.can_interact?(character, vendor_guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(vendor_guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, vendor_guid) do
      true
    else
      _ -> false
    end
  end

  defp buy_authorized(state, character, vendor_guid, item_id, count) do
    case Enum.find(visible_items(character, vendor_guid), &(&1.template.entry == item_id)) do
      %{template: template} = vendor_item ->
        buy_visible(state, character, vendor_guid, vendor_item, template, count)

      _missing_or_condition_failed ->
        send_buy_failed(vendor_guid, item_id, :cant_find_item)
        state
    end
  end

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

      not ItemRequirements.can_buy?(character, template) ->
        send_buy_failed(vendor_guid, template.entry, :rank_require)
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
    purchase = %{character | player: %{character.player | coinage: character.player.coinage - price}}

    case Items.store(%{state | character: purchase}, template, total_count) do
      {:ok, state, {bag_slot, item_slot}} ->
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
