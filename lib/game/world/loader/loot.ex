defmodule ThistleTea.Game.World.Loader.Loot do
  @moduledoc """
  Generates a loot instance for a loot id by feeding Mangos loot-template rows
  through the pure loot roller.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    creature = Mangos.Repo.all(Mangos.CreatureLootTemplate)
    gameobject = Mangos.Repo.all(Mangos.GameObjectLootTemplate)
    fishing = Mangos.Repo.all(Mangos.FishingLootTemplate)
    references = Mangos.Repo.all(Mangos.ReferenceLootTemplate)

    cache_rows(:creature, creature)
    cache_rows(:gameobject, gameobject)
    cache_rows(:fishing, fishing)
    cache_rows(:reference, references)

    [creature, gameobject, fishing, references]
    |> List.flatten()
    |> Enum.map(& &1.item)
    |> Enum.filter(&(&1 > 0))
    |> Enum.uniq()
    |> Enum.each(&ItemLoader.get_template/1)

    :ets.insert(__MODULE__, {:loaded, true})
    :ok
  end

  def load_fishing, do: load_all()

  def generate(loot_id, min_gold, max_gold, wanted_quest_item? \\ &always_wanted/1) do
    %Loot{
      gold: roll_gold(min_gold, max_gold),
      items: roll_items(loot_id, &creature_rows/1, wanted_quest_item?)
    }
  end

  def generate_gameobject(loot_id, min_gold, max_gold) do
    %Loot{
      gold: roll_gold(min_gold, max_gold),
      items: roll_items(loot_id, &gameobject_rows/1)
    }
  end

  def generate_fishing(area_id, zone_id) do
    loot_id = if fishing_rows(area_id) == [], do: zone_id, else: area_id
    %Loot{items: roll_items(loot_id, &fishing_rows/1)}
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

  defp roll_items(loot_id, rows_fn, wanted_quest_item? \\ &always_wanted/1)

  defp roll_items(loot_id, rows_fn, wanted_quest_item?) when is_integer(loot_id) and loot_id > 0 do
    loot_id
    |> rows_fn.()
    |> Loot.roll(&reference_rows/1)
    |> Enum.filter(fn {item_id, _count, quest_item, _condition} -> not quest_item or wanted_quest_item?.(item_id) end)
    |> Enum.map(fn {item_id, count, quest_item, condition} ->
      {ItemLoader.get_template(item_id), count, quest_item, condition}
    end)
    |> Enum.reject(fn {template, _count, _quest_item, _condition} -> is_nil(template) end)
    |> Enum.with_index()
    |> Enum.map(fn {{%ItemTemplate{} = template, count, quest_item, condition}, index} ->
      %Loot.Item{
        slot: index,
        item_id: template.entry,
        display_id: template.display_id,
        count: count,
        quality: template.quality,
        quest_item: quest_item,
        condition: condition
      }
    end)
  end

  defp roll_items(_loot_id, _rows_fn, _wanted_quest_item?), do: []

  defp always_wanted(_item_id), do: true

  defp creature_rows(loot_id) do
    case :ets.lookup(__MODULE__, {:creature, loot_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        load_missing(:creature, loot_id, Mangos.CreatureLootTemplate)
    end
  end

  defp gameobject_rows(loot_id) do
    case :ets.lookup(__MODULE__, {:gameobject, loot_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        load_missing(:gameobject, loot_id, Mangos.GameObjectLootTemplate)
    end
  end

  defp fishing_rows(area_id) do
    case :ets.lookup(__MODULE__, {:fishing, area_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        []
    end
  end

  defp reference_rows(entry) do
    case :ets.lookup(__MODULE__, {:reference, entry}) do
      [{_key, rows}] ->
        rows

      _ ->
        load_missing(:reference, entry, Mangos.ReferenceLootTemplate)
    end
  end

  defp load_missing(kind, entry, schema) do
    case :ets.lookup(__MODULE__, :loaded) do
      [{:loaded, true}] -> []
      _not_preloaded -> entry |> schema.query() |> Mangos.Repo.all() |> rows() |> then(&cache({kind, entry}, &1))
    end
  end

  defp rows(template_rows) do
    conditions =
      template_rows
      |> Enum.map(& &1.condition_id)
      |> ConditionLoader.load_by_ids()

    Enum.map(template_rows, &row(&1, conditions))
  end

  defp cache_rows(kind, template_rows) do
    template_rows
    |> rows()
    |> Enum.group_by(& &1.entry)
    |> Enum.each(fn {entry, entry_rows} -> cache({kind, entry}, entry_rows) end)
  end

  defp row(template_row, conditions) do
    %{
      entry: template_row.entry,
      item: template_row.item,
      chance: template_row.chance,
      groupid: template_row.groupid,
      mincount_or_ref: template_row.mincount_or_ref,
      maxcount: template_row.maxcount,
      condition: Map.get(conditions, template_row.condition_id)
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
