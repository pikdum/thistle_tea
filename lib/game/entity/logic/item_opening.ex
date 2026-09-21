defmodule ThistleTea.Game.Entity.Logic.ItemOpening do
  @moduledoc """
  Private container eligibility and atomic loot claims. Rolled contents belong
  to the item instance until its owner empties and releases the container.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Loot

  def validate(%Character{} = character, %Item{} = item) do
    cond do
      Core.dead?(character) ->
        {:error, :you_are_dead}

      not is_nil(character.internal.taxi_flight) ->
        {:error, :cant_do_right_now}

      item.item.owner != character.object.guid ->
        {:error, :dont_own_that_item}

      Item.container?(item) or not (Item.wrapped?(item) or openable?(Item.template(item))) ->
        {:error, :cant_do_right_now}

      locked?(item) ->
        {:error, :item_locked}

      true ->
        :ok
    end
  end

  def validate(_character, _item), do: {:error, :item_not_found}

  def validate_unlock(%Item{} = item) do
    if locked?(item), do: :ok, else: {:error, :already_open}
  end

  def validate_unlock(_item), do: {:error, :item_gone}

  defp locked?(item), do: Item.template(item).lockid > 0 and not Item.unlocked?(item)

  defp openable?(%ItemTemplate{flags: flags, lockid: lockid}), do: (flags &&& 4) != 0 or lockid > 0

  def claim(%Character{} = character, %Item{} = source, slot, %Item{} = item, get_item) do
    with :ok <- validate(character, source),
         %Loot{} = loot <- Item.loot(source),
         {:ok, reward, remaining} <- Loot.commit_item(loot, slot),
         true <- reward.item_id == item.object.entry and reward.count == item.item.stack_count,
         true <- item.item.owner == character.object.guid do
      character.player
      |> Batch.new()
      |> Batch.add(item)
      |> Batch.update(Item.put_loot(source, remaining))
      |> Inventory.plan(get_item)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :already_looted}
    end
  end

  def take_gold(%Character{} = character, %Item{} = source, get_item) do
    with :ok <- validate(character, source),
         %Loot{gold: gold} = loot when gold > 0 <- Item.loot(source),
         money = character.player.coinage + gold,
         true <- money <= 2_147_483_647,
         {:ok, changes} <-
           %{character.player | coinage: money}
           |> Batch.new()
           |> Batch.update(Item.put_loot(source, %{loot | gold: 0}))
           |> Inventory.plan(get_item) do
      {:ok, gold, changes}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :cant_do_right_now}
    end
  end

  def release(%Character{} = character, %Item{} = source, get_item) do
    with true <- source.item.owner == character.object.guid,
         %Loot{} = loot <- Item.loot(source),
         true <- Loot.empty?(loot) do
      character.player
      |> Batch.new()
      |> Batch.remove_item(source.object.guid, source.item.stack_count)
      |> Inventory.plan(get_item)
    else
      _ -> :unchanged
    end
  end
end
