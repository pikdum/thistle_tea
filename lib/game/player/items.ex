defmodule ThistleTea.Game.Player.Items do
  @moduledoc """
  Grants and consumes items for a player session: creates or removes the item
  instance, updates the inventory, and sends the client packets. Used by
  item-creating spells, consumable on-use items, and the `.additem` dev
  command.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Crafting
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Entity.Logic.Loot
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
    items =
      case ItemLoader.get_template(item_id) do
        %ItemTemplate{} = template when count > 0 -> prepare_stacks(template, state.guid, count)
        _ -> :item_not_found
      end

    case store_prepared(state, items, recipe, 1) do
      {:ok, state} ->
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
    store_template(state, template, count, recipe, [])
  end

  def store(state, %Loot.Item{} = reward, count, recipe) when is_integer(count) and count > 0 do
    case ItemLoader.get_template(reward.item_id) do
      %ItemTemplate{} = template ->
        store_template(state, template, count, recipe, random_property: reward.random_property)

      _ ->
        {:error, :item_not_found, state}
    end
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

  defp store_template(state, template, count, recipe, opts) do
    case plan_store(state.character, template, count, opts) do
      {:ok, changes, position} -> {:ok, commit_store(state, changes, recipe), position}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def plan_store(%Character{} = character, %ItemTemplate{} = template, count, opts \\ [])
      when is_integer(count) and count > 0 do
    items = prepare_stacks(template, character.object.guid, count, opts)
    batch = Enum.reduce(items, Batch.new(character.player), &Batch.add(&2, &1))

    with {:ok, changes} <- Inventory.plan(batch, &ItemStore.get/1) do
      position = placement_position(ChangeSet.placement(changes, hd(items).object.guid))
      {:ok, changes, position}
    end
  end

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

    store_prepared(state, items, nil, 0)
  end

  defp store_prepared(state, items, recipe, created) when is_list(items) do
    batch = Enum.reduce(items, Batch.new(state.character.player), &Batch.add(&2, &1))

    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} ->
        state = commit_store(state, changes, recipe)

        Enum.each(items, fn item ->
          position = placement_position(ChangeSet.placement(changes, item.object.guid))
          send_push_result(state, item, item.item.stack_count, position, created)
        end)

        {:ok, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp store_prepared(state, reason, _recipe, _created), do: {:error, reason, state}

  defp commit_store(state, changes, recipe) do
    character = Crafting.skill_up(%{state.character | player: changes.player}, recipe, :rand.uniform(100) - 1)
    changes = ChangeSet.put_player(changes, character.player)
    InventoryUpdate.apply(state, {:ok, changes})
  end

  defp prepare_stacks(template, owner, count, opts \\ [])
  defp prepare_stacks(_template, _owner, 0, _opts), do: []

  defp prepare_stacks(%ItemTemplate{} = template, owner, count, opts) do
    stack_count = min(count, max(template.stackable || 1, 1))
    item = ItemStore.prepare(template, Keyword.merge(opts, owner: owner, stack_count: stack_count))
    [item | prepare_stacks(template, owner, count - stack_count, opts)]
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

  def send_push_result(state, item, count, position, created \\ 0)

  def send_push_result(state, %DataItem{} = item, count, position, created) do
    reward = %Loot.Item{item_id: item.object.entry, random_property: DataItem.random_property(item)}
    send_push_result(state, reward, count, position, created)
  end

  def send_push_result(state, %Loot.Item{} = reward, count, {bag_slot, item_slot}, created) do
    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: state.guid,
      item_id: reward.item_id,
      random_property_id: ItemProperty.id(reward.random_property),
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: count,
      created: created
    })
  end

  def send_push_result(state, item_id, count, position, created) do
    item = state.character.player |> Inventory.item_guid_at(position, &ItemStore.get/1) |> ItemStore.get()
    reward = if match?(%DataItem{object: %{entry: ^item_id}}, item), do: item, else: %Loot.Item{item_id: item_id}
    send_push_result(state, reward, count, position, created)
  end

  defp system_message(state, message) do
    Network.send_packet(Message.SmsgMessagechat.system(message, state.guid))
    state
  end
end
