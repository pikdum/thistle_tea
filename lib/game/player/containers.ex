defmodule ThistleTea.Game.Player.Containers do
  @moduledoc """
  Opens private inventory containers from cached loot templates. Every claim
  rechecks ownership and bank access, then commits source loot and rewards
  through one inventory transaction.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.ItemOpening
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Bank
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  def open(%{character: %Character{} = character} = state, position) do
    guid = Inventory.item_guid_at(character.player, position, &ItemStore.get/1)
    open_guid(state, guid)
  end

  def open(state, _position), do: state

  def open_guid(state, guid, loot_type \\ 1) when loot_type in [1, 2] do
    with {:ok, state, item} <- authorize(state, guid),
         :ok <- ItemOpening.validate(state.character, item) do
      state |> Looting.release() |> Spellcasting.cancel() |> open_current(guid, loot_type)
    else
      {:error, reason} -> failure(state, reason, guid)
    end
  end

  defp open_current(state, guid, loot_type) do
    with {:ok, state, item} <- authorize(state, guid),
         item = ensure_loot(state.character, item),
         {:ok, changes} <-
           state.character.player |> Batch.new() |> Batch.update(item) |> Inventory.plan(&ItemStore.get/1) do
      state = InventoryUpdate.apply(state, {:ok, changes})
      Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: Item.loot(item), loot_type: loot_type})
      state = %{state | loot_guid: guid, loot_type: :container}
      if Loot.empty?(Item.loot(item)), do: Looting.release(state), else: state
    else
      {:error, reason} -> failure(state, reason, guid)
    end
  end

  def take_item(%{loot_type: :container, loot_guid: guid} = state, slot) do
    with {:ok, state, source} <- authorize(state, guid),
         %Loot{} = loot <- Item.loot(source),
         %Loot.Item{} = reward <- Enum.find(loot.items, &(&1.slot == slot and not &1.looted)),
         %Item{} = item <- ItemStore.prepare(reward.item_id, owner: state.guid, stack_count: reward.count),
         {:ok, changes} <- ItemOpening.claim(state.character, source, slot, item, &ItemStore.get/1) do
      state = InventoryUpdate.apply(state, {:ok, changes})
      Network.send_packet(%Message.SmsgLootRemoved{slot: slot})
      Items.send_push_result(state, reward.item_id, reward.count, position(changes, item.object.guid))
      state
    else
      {:error, reason} -> failure(state, reason, guid)
      _ -> failure(state, :already_looted, guid)
    end
  end

  def take_item(state, _slot), do: state

  def take_money(%{loot_type: :container, loot_guid: guid} = state) do
    with {:ok, state, source} <- authorize(state, guid),
         {:ok, gold, changes} <- ItemOpening.take_gold(state.character, source, &ItemStore.get/1) do
      state = InventoryUpdate.apply(state, {:ok, changes})
      Network.send_packet(%Message.SmsgLootMoneyNotify{money: gold})
      Network.send_packet(%Message.SmsgLootClearMoney{})
      state
    else
      {:error, reason} -> failure(state, reason, guid)
    end
  end

  def take_money(state), do: state

  def release(%{character: %Character{} = character, loot_guid: guid} = state) do
    with %Item{} = item <- owned_item(character, guid),
         {:ok, changes} <- ItemOpening.release(character, item, &ItemStore.get/1) do
      InventoryUpdate.apply(state, {:ok, changes})
    else
      _ -> state
    end
  end

  def release(state), do: state

  def available?(state, guid) do
    match?({:ok, _, _}, authorize(state, guid))
  end

  defp authorize(%{character: %Character{} = character, active_mover_guid: mover, guid: owner} = state, guid)
       when is_integer(guid) and mover in [nil, 0, owner] do
    with position when not is_nil(position) <-
           Inventory.find_position(character.player, guid, :all_owned, &ItemStore.get/1),
         {:ok, state} <- Bank.authorize_positions(state, [position]),
         %Item{} = item <- owned_item(character, guid) do
      {:ok, state, item}
    else
      {:error, _state} -> {:error, :too_far_away_from_bank}
      _ -> {:error, :item_not_found}
    end
  end

  defp authorize(_state, _guid), do: {:error, :item_not_found}

  defp owned_item(character, guid) do
    with position when not is_nil(position) <-
           Inventory.find_position(character.player, guid, :all_owned, &ItemStore.get/1),
         %Item{item: %{owner: owner}} = item when owner == character.object.guid <- ItemStore.get(guid) do
      item
    else
      _ -> nil
    end
  end

  defp ensure_loot(character, item) do
    if Item.loot_generated?(item), do: item, else: Item.put_loot(item, generate(character, item))
  end

  defp generate(character, item) do
    template = Item.template(item)
    needed = Quests.needed_items(character)

    loot =
      LootLoader.generate_item(
        template.entry,
        template.min_money_loot,
        template.max_money_loot,
        &MapSet.member?(needed, &1)
      )

    conditions = Enum.map(loot.items, & &1.condition)
    source = %Subject{guid: item.object.guid, kind: :item, entry: item.object.entry, owner_guid: character.object.guid}
    context = ConditionContext.build(character, conditions, source: source)
    items = Enum.filter(loot.items, &(is_nil(&1.condition) or Condition.evaluate(context, &1.condition) == :met))
    %{loot | items: items}
  end

  defp position(changes, guid) do
    case ChangeSet.placement(changes, guid) do
      %Placement{status: :placed, position: position} -> position
      %Placement{status: :merged} -> {Inventory.bag_0(), 0xFFFFFFFF}
    end
  end

  defp failure(state, reason, guid) do
    InventoryUpdate.send_failure(reason, guid || 0, 0)
    state
  end
end
