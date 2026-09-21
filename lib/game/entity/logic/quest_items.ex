defmodule ThistleTea.Game.Entity.Logic.QuestItems do
  @moduledoc """
  Quest source-item counts and atomic abandonment inventory requests.
  Source counts include bank storage. Abandonment consumes quest-bound
  objectives and restores a distinct quest-starting item when appropriate.
  """

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch

  def missing_source_count(%Player{} = player, %Quest{} = quest, get_item) do
    if quest.src_item_id > 0 do
      max(max(quest.src_item_count, 1) - Inventory.count_entry_with_bank(player, quest.src_item_id, get_item), 0)
    else
      0
    end
  end

  def abandon(%Player{} = player, %Quest{} = quest, get_item) do
    items = Inventory.all_owned_items(player, get_item)
    {source_counts, replacements} = source_removals(items, quest)
    objective_ids = MapSet.new(quest.required_items, fn {_slot, entry, _count} -> entry end)

    {batch, _remaining} =
      Enum.reduce(items, {Batch.new(player), source_counts}, fn %Item{} = item, {batch, remaining} ->
        entry = item.object.entry
        count = item.item.stack_count || 1
        source_count = min(count, Map.get(remaining, entry, 0))
        remaining = Map.update(remaining, entry, 0, &max(&1 - source_count, 0))

        remove_count =
          if MapSet.member?(objective_ids, entry) and Item.template(item).bonding in [4, 5],
            do: count,
            else: source_count

        batch = if remove_count > 0, do: Batch.consume_item(batch, item.object.guid, remove_count), else: batch
        {batch, remaining}
      end)

    {batch, replacements}
  end

  defp source_removals(items, %Quest{} = quest) do
    source_items = Enum.filter(items, &(&1.object.entry == quest.src_item_id))
    count = max(quest.src_item_count, 1)
    available = Enum.sum(Enum.map(source_items, &(&1.item.stack_count || 1)))
    starts_quest? = Enum.any?(source_items, &(Item.template(&1).start_quest == quest.id))

    if quest.src_item_id > 0 and available >= count and not starts_quest? do
      replacements =
        case quest.start_item_template do
          %ItemTemplate{} = template -> [{template, count}]
          nil -> []
        end

      {%{quest.src_item_id => count}, replacements}
    else
      {%{}, []}
    end
  end
end
