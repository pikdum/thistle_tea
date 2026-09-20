defmodule ThistleTea.Game.Player.Items do
  @moduledoc """
  Grants and consumes items for a player session: creates or removes the item
  instance, updates the inventory, and sends the client packets. Used by
  item-creating spells, consumable on-use items, and the `.additem` dev
  command.
  """
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  def create(state, item_id, count) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{} = template ->
        count = Inventory.limit_new_count(state.character.player, template, count, &ItemStore.get/1)
        if count > 0, do: give(state, item_id, count), else: state

      _missing ->
        state
    end
  end

  def give(state, item_id, count) do
    case store(state, item_id, count) do
      {:ok, state, placed_at} ->
        send_push_result(state, item_id, count, placed_at, 1)
        state

      {:error, :item_not_found, state} ->
        system_message(state, "Item #{item_id} not found.")

      {:error, :cant_carry_more_of_this, state} ->
        InventoryUpdate.send_failure(:cant_carry_more_of_this, 0, 0)
        state

      {:error, _reason, state} ->
        system_message(state, "Inventory full.")
    end
  end

  def store(state, item_id, count) when is_integer(count) and count > 0 do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{} = template ->
        items = prepare_stacks(template, state.guid, count)
        batch = Enum.reduce(items, Batch.new(state.character.player), &Batch.add(&2, &1))
        commit_stacks(state, batch, hd(items).object.guid)

      _ ->
        {:error, :item_not_found, state}
    end
  end

  def store(state, _item_id, _count), do: {:error, :item_not_found, state}

  defp prepare_stacks(_template, _owner, 0), do: []

  defp prepare_stacks(%ItemTemplate{} = template, owner, count) do
    stack_count = min(count, max(template.stackable || 1, 1))
    item = ItemStore.prepare(template, owner: owner, stack_count: stack_count)
    [item | prepare_stacks(template, owner, count - stack_count)]
  end

  defp commit_stacks(state, batch, first_guid) do
    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} ->
        position = placement_position(ChangeSet.placement(changes, first_guid))
        {:ok, InventoryUpdate.apply(state, {:ok, changes}), position}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp placement_position(%Placement{status: :placed, position: position}), do: position
  defp placement_position(%Placement{status: :merged}), do: {Inventory.bag_0(), 0xFFFFFFFF}

  def consume(state, item_guid) when is_integer(item_guid) do
    with %DataItem{} = item <- ItemStore.get(item_guid),
         {_bag, _slot} = pos <- Inventory.find_position(state.character.player, item_guid, &ItemStore.get/1) do
      consume_at(state, item, pos)
    else
      _ -> state
    end
  end

  def consume(state, _item_guid), do: state

  defp consume_at(state, %DataItem{} = item, pos) do
    get_item = &ItemStore.get/1

    if (item.item.stack_count || 1) > 1 do
      case Inventory.reduce_stack(state.character.player, pos, 1, get_item) do
        {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
        _ -> state
      end
    else
      case Inventory.destroy(state.character.player, pos, get_item) do
        {:ok, result, _item} ->
          ItemStore.delete(item.object.guid)
          Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
          InventoryUpdate.apply(state, {:ok, result})

        _ ->
          state
      end
    end
  end

  def send_push_result(state, item_id, count, {bag_slot, item_slot}, created \\ 0) do
    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: state.guid,
      item_id: item_id,
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: count,
      created: created
    })
  end

  defp system_message(state, message) do
    Network.send_packet(Message.SmsgMessagechat.system(message, state.guid))
    state
  end
end
