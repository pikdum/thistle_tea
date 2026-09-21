defmodule ThistleTea.Game.Entity.Logic.ItemWrapping do
  @moduledoc """
  Gift eligibility and atomic wrapping-paper consumption. Opening restores
  the original item in place without creating loot or resetting its fields.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.ItemOpening

  def wrap(%Character{} = character, paper_position, target_position, gift, get_item) do
    with :ok <- available(character),
         {:ok, paper} <- owned_item(character, paper_position, get_item),
         {:ok, item} <- owned_item(character, target_position, get_item),
         :ok <- paper_matches(paper, gift),
         :ok <- wrappable(item, paper, target_position) do
      character.player
      |> Batch.new()
      |> Batch.consume_item(paper.object.guid, 1)
      |> Batch.update(Item.wrap(item, gift, character.object.guid))
      |> Inventory.plan(get_item)
    end
  end

  def unwrap(%Character{} = character, %Item{} = item, get_item) do
    with :ok <- ItemOpening.validate(character, item),
         true <- Item.wrapped?(item),
         {:ok, original} <- Item.unwrap(item) do
      character.player |> Batch.new() |> Batch.update(original) |> Inventory.plan(get_item)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :cant_do_right_now}
    end
  end

  defp available(character) do
    cond do
      Core.dead?(character) -> {:error, :you_are_dead}
      not is_nil(character.internal.casting) -> {:error, :cant_do_right_now}
      not is_nil(character.internal.taxi_flight) -> {:error, :cant_do_right_now}
      true -> :ok
    end
  end

  defp owned_item(character, position, get_item) do
    with guid when is_integer(guid) and guid > 0 <- Inventory.item_guid_at(character.player, position, get_item),
         %Item{item: %{owner: owner}} = item when owner == character.object.guid <- get_item.(guid) do
      {:ok, item}
    else
      _ -> {:error, :item_not_found}
    end
  end

  defp paper_matches(paper, %ItemTemplate{entry: entry, flags: flags, stackable: 1, container_slots: 0}) do
    template = Item.template(paper)

    if (template.flags &&& 512) != 0 and template.wrapped_gift == entry and (flags &&& 512) != 0 and
         not Item.wrapped?(paper),
       do: :ok,
       else: {:error, :item_not_found}
  end

  defp paper_matches(_paper, _gift), do: {:error, :item_not_found}

  defp wrappable(item, paper, position) do
    cond do
      item.object.guid == paper.object.guid -> {:error, :wrapped_cant_be_wrapped}
      equipped?(position) -> {:error, :equipped_cant_be_wrapped}
      Item.wrapped?(item) or item.item.gift_creator not in [nil, 0] -> {:error, :wrapped_cant_be_wrapped}
      true -> wrappable_contents(item)
    end
  end

  defp wrappable_contents(item) do
    template = Item.template(item)

    cond do
      Item.container?(item) -> {:error, :bags_cant_be_wrapped}
      ((item.item.flags || 0) &&& 1) != 0 -> {:error, :bound_cant_be_wrapped}
      template.stackable != 1 or item.item.stack_count != 1 -> {:error, :stackable_cant_be_wrapped}
      template.max_count > 0 -> {:error, :unique_cant_be_wrapped}
      Item.loot_generated?(item) -> {:error, :item_locked}
      true -> :ok
    end
  end

  defp equipped?({255, slot}), do: Inventory.equipment_slot?(slot) or Inventory.bag_slot?(slot)
  defp equipped?(_position), do: false
end
