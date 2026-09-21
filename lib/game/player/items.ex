defmodule ThistleTea.Game.Player.Items do
  @moduledoc """
  Grants and consumes items for a player session: creates or removes the item
  instance, updates the inventory, and sends the client packets. Used by
  item-creating spells, consumable on-use items, and the `.additem` dev
  command.
  """
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Crafting
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader

  def create(state, item_id, count, spell_id \\ nil) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{} = template ->
        count = Inventory.limit_new_count(state.character.player, template, count, &ItemStore.get/1)
        if count > 0, do: give(state, item_id, count, SkillLoader.recipe(spell_id)), else: state

      _missing ->
        state
    end
  end

  def give(state, item_id, count), do: give(state, item_id, count, nil)

  defp give(state, item_id, count, recipe) do
    case store(state, item_id, count, recipe) do
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

  def store(state, item_id, count, recipe \\ nil)

  def store(state, %ItemTemplate{} = template, count, recipe) when is_integer(count) and count > 0 do
    items = prepare_stacks(template, state.guid, count)
    batch = Enum.reduce(items, Batch.new(state.character.player), &Batch.add(&2, &1))
    commit_stacks(state, batch, hd(items).object.guid, recipe)
  end

  def store(state, item_id, count, recipe) when is_integer(count) and count > 0 do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{} = template ->
        store(state, template, count, recipe)

      _ ->
        {:error, :item_not_found, state}
    end
  end

  def store(state, _item_id, _count, _recipe), do: {:error, :item_not_found, state}

  def store_many(state, entries) when is_list(entries) do
    items =
      Enum.reduce_while(entries, [], fn {entry, count}, items ->
        case ItemLoader.get_template(entry) do
          %ItemTemplate{} = template when is_integer(count) and count > 0 ->
            {:cont, items ++ prepare_stacks(template, state.guid, count)}

          _ ->
            {:halt, :item_not_found}
        end
      end)

    store_prepared(state, items)
  end

  defp store_prepared(state, items) when is_list(items) do
    batch = Enum.reduce(items, Batch.new(state.character.player), &Batch.add(&2, &1))

    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} ->
        state = InventoryUpdate.apply(state, {:ok, changes})

        Enum.each(items, fn item ->
          position = placement_position(ChangeSet.placement(changes, item.object.guid))
          send_push_result(state, item.object.entry, item.item.stack_count, position)
        end)

        {:ok, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp store_prepared(state, reason), do: {:error, reason, state}

  defp prepare_stacks(_template, _owner, 0), do: []

  defp prepare_stacks(%ItemTemplate{} = template, owner, count) do
    stack_count = min(count, max(template.stackable || 1, 1))
    item = ItemStore.prepare(template, owner: owner, stack_count: stack_count)
    [item | prepare_stacks(template, owner, count - stack_count)]
  end

  defp commit_stacks(state, batch, first_guid, recipe) do
    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} ->
        character = Crafting.skill_up(%{state.character | player: changes.player}, recipe, :rand.uniform(100) - 1)
        changes = ChangeSet.put_player(changes, character.player)
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

  def consume_cast_item(state, item_guid) do
    with %DataItem{} = item <- ItemStore.get(item_guid),
         {_bag, _slot} <- Inventory.find_position(state.character.player, item_guid, &ItemStore.get/1),
         {:ok, _spell_id, index, _commit?} <- ItemUse.on_use_spell(item),
         {:ok, batch} <- ItemUse.plan(Batch.new(state.character.player), item, index),
         {:ok, changes} <- Inventory.plan(batch, &ItemStore.get/1) do
      InventoryUpdate.apply(state, {:ok, changes})
    else
      _ -> state
    end
  end

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
