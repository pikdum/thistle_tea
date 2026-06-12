defmodule ThistleTea.Game.World.Loader.Loot do
  @moduledoc """
  Generates a loot instance for a loot id by feeding Mangos loot-template rows
  through the pure loot roller.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  def generate(loot_id, min_gold, max_gold) do
    %Loot{
      gold: roll_gold(min_gold, max_gold),
      items: roll_items(loot_id)
    }
  end

  defp roll_items(loot_id) when is_integer(loot_id) and loot_id > 0 do
    Mangos.CreatureLootTemplate.query(loot_id)
    |> Mangos.Repo.all()
    |> Loot.roll(&reference_rows/1)
    |> Enum.map(fn {item_id, count, quest_item} -> {ItemLoader.get_template(item_id), count, quest_item} end)
    |> Enum.reject(fn {template, _count, _quest_item} -> is_nil(template) end)
    |> Enum.with_index()
    |> Enum.map(fn {{%ItemTemplate{} = template, count, quest_item}, index} ->
      %Loot.Item{
        slot: index,
        item_id: template.entry,
        display_id: template.display_id,
        count: count,
        quality: template.quality,
        quest_item: quest_item
      }
    end)
  end

  defp roll_items(_loot_id), do: []

  defp reference_rows(entry) do
    Mangos.ReferenceLootTemplate.query(entry)
    |> Mangos.Repo.all()
  end

  defp roll_gold(min_gold, max_gold) when is_integer(min_gold) and is_integer(max_gold) and max_gold > 0 do
    Enum.random(min_gold..max(max_gold, min_gold))
  end

  defp roll_gold(_min_gold, _max_gold), do: 0
end
