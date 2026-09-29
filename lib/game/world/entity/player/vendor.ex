defmodule ThistleTea.Game.World.Entity.Player.Vendor do
  @moduledoc """
  Owns condition-aware vendor listing, live vendor authorization, and purchases.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Honor.ItemRequirements
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.ItemCosts
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.VendorPurchase
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.VendorStock

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

  def buy(state, vendor_guid, item_id, requested_count, destination \\ :carried)

  def buy(
        %{ready: true, character: %Character{} = character} = state,
        vendor_guid,
        item_id,
        requested_count,
        destination
      ) do
    if valid_vendor?(character, vendor_guid) do
      state = state |> VendorPurchase.settle() |> ItemCosts.settle()
      buy_authorized(state, vendor_guid, item_id, max(requested_count, 1), destination)
    else
      send_buy_failed(vendor_guid, item_id, :distance_too_far)
      state
    end
  end

  def buy(state, _vendor_guid, _item_id, _count, _destination), do: state

  def buy_in_slot(%{ready: true, character: %Character{} = character} = state, vendor, item, count, bag_guid, slot) do
    with bag when is_integer(bag) <- destination_bag(character, bag_guid),
         true <- slot == 255 or Inventory.carried_position?({bag, slot}) do
      destination = if slot == 255, do: {:bag, bag}, else: {bag, slot}
      buy(state, vendor, item, count, destination)
    else
      nil ->
        state

      false ->
        InventoryUpdate.send_failure(:item_doesnt_go_to_slot, 0, 0)
        state
    end
  end

  def buy_in_slot(state, _vendor, _item, _count, _bag, _slot), do: state

  defp destination_bag(%Character{object: %{guid: guid}}, guid), do: Inventory.bag_0()

  defp destination_bag(%Character{} = character, guid) do
    Enum.find(Inventory.slot_index(:bag1)..Inventory.slot_index(:bag4), fn slot ->
      with ^guid <- Inventory.item_guid_at(character.player, {Inventory.bag_0(), slot}, &ItemStore.get/1),
           %Item{item: %{owner: owner}} = item <- ItemStore.get(guid) do
        owner == character.object.guid and Item.container?(item)
      else
        _missing -> false
      end
    end)
  end

  def valid_vendor?(%Character{} = character, vendor_guid) do
    with true <- Death.alive?(character),
         :mob <- Guid.entity_type(vendor_guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(vendor_guid, [:alive?, :npc_flags]),
         true <- (flags &&& 0x4) != 0,
         true <- Reputation.can_interact?(character, vendor_guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(vendor_guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, vendor_guid) do
      true
    else
      _ -> false
    end
  end

  defp buy_authorized(state, vendor_guid, item_id, count, destination) do
    case Enum.find(visible_items(state.character, vendor_guid), &(&1.template.entry == item_id)) do
      %{template: _template} = vendor_item ->
        buy_visible(state, vendor_guid, vendor_item, count, destination)

      _missing_or_condition_failed ->
        send_buy_failed(vendor_guid, item_id, :cant_find_item)
        state
    end
  end

  def visible_items(%Character{} = character, vendor_guid) do
    items = VendorLoader.items(World.entry(vendor_guid))
    conditions = Enum.map(items, &condition_of/1)

    visible = condition_visible_items(character, vendor_guid, items, conditions)
    priced = Reputation.vendor_items(character, vendor_guid, visible)
    VendorStock.list(character.internal.world, vendor_guid, priced)
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
    source = %Subject{guid: vendor_guid, kind: :mob, entry: World.entry(vendor_guid), alive?: true}
    ConditionContext.build(character, conditions, source: source)
  end

  defp buy_visible(state, vendor_guid, vendor_item, count, destination) do
    character = state.character
    template = vendor_item.template
    price = Reputation.price(character, vendor_guid, template.buy_price * count)

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

      true ->
        VendorPurchase.buy(state, vendor_guid, vendor_item, count, price, destination)
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
