defmodule ThistleTea.Game.World.Loader.Loot do
  @moduledoc """
  Generates a loot instance for a loot id by feeding Mangos loot-template rows
  through the pure loot roller.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def generate(loot_id, min_gold, max_gold) do
    %Loot{
      gold: roll_gold(min_gold, max_gold),
      items: roll_items(loot_id)
    }
  end

  def generate_fixed(items, gold) do
    items =
      items
      |> Enum.map(fn {item_id, count} -> {ItemLoader.get_template(item_id), count} end)
      |> Enum.reject(fn {template, _count} -> is_nil(template) end)
      |> Enum.with_index()
      |> Enum.map(fn {{%ItemTemplate{} = template, count}, index} ->
        %Loot.Item{
          slot: index,
          item_id: template.entry,
          display_id: template.display_id,
          count: count,
          quality: template.quality
        }
      end)

    %Loot{gold: gold, items: items}
  end

  defp roll_items(loot_id) when is_integer(loot_id) and loot_id > 0 do
    loot_id
    |> creature_rows()
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

  defp creature_rows(loot_id) do
    case :ets.lookup(__MODULE__, {:creature, loot_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        rows = Mangos.CreatureLootTemplate.query(loot_id) |> Mangos.Repo.all() |> Enum.map(&row/1)
        cache({:creature, loot_id}, rows)
    end
  end

  defp reference_rows(entry) do
    case :ets.lookup(__MODULE__, {:reference, entry}) do
      [{_key, rows}] ->
        rows

      _ ->
        rows = Mangos.ReferenceLootTemplate.query(entry) |> Mangos.Repo.all() |> Enum.map(&row/1)
        cache({:reference, entry}, rows)
    end
  end

  defp row(template_row) do
    %{
      item: template_row.item,
      chance: template_row.chance,
      groupid: template_row.groupid,
      mincount_or_ref: template_row.mincount_or_ref,
      maxcount: template_row.maxcount
    }
  end

  defp cache(key, rows) do
    :ets.insert(__MODULE__, {key, rows})
    rows
  end

  defp roll_gold(min_gold, max_gold) when is_integer(min_gold) and is_integer(max_gold) and max_gold > 0 do
    Enum.random(min_gold..max(max_gold, min_gold))
  end

  defp roll_gold(_min_gold, _max_gold), do: 0
end
