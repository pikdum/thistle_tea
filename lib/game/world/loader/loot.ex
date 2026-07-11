defmodule ThistleTea.Game.World.Loader.Loot do
  @moduledoc """
  Generates a loot instance for a loot id by feeding Mangos loot-template rows
  through the pure loot roller.
  """
  import Ecto.Query

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

  def load_fishing do
    rows = Mangos.Repo.all(Mangos.FishingLootTemplate)

    rows
    |> Enum.group_by(& &1.entry, &row/1)
    |> Enum.each(fn {entry, entry_rows} -> :ets.insert(__MODULE__, {{:fishing, entry}, entry_rows}) end)

    rows
    |> Enum.map(& &1.item)
    |> Enum.filter(&(&1 > 0))
    |> Enum.uniq()
    |> Enum.each(&ItemLoader.get_template/1)

    _references =
      rows
      |> Enum.map(& &1.mincount_or_ref)
      |> Enum.filter(&(&1 < 0))
      |> Enum.reduce(MapSet.new(), fn reference, seen -> preload_reference(-reference, seen) end)

    Mangos.Repo.all(from(g in Mangos.GameObjectTemplate, where: g.type == 25, select: g.data1, distinct: true))
    |> Enum.filter(&(&1 > 0))
    |> Enum.each(&preload_gameobject/1)

    :ok
  end

  def generate(loot_id, min_gold, max_gold) do
    %Loot{
      gold: roll_gold(min_gold, max_gold),
      items: roll_items(loot_id, &creature_rows/1)
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

  defp roll_items(loot_id, rows_fn) when is_integer(loot_id) and loot_id > 0 do
    loot_id
    |> rows_fn.()
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

  defp roll_items(_loot_id, _rows_fn), do: []

  defp creature_rows(loot_id) do
    case :ets.lookup(__MODULE__, {:creature, loot_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        rows = Mangos.CreatureLootTemplate.query(loot_id) |> Mangos.Repo.all() |> Enum.map(&row/1)
        cache({:creature, loot_id}, rows)
    end
  end

  defp gameobject_rows(loot_id) do
    case :ets.lookup(__MODULE__, {:gameobject, loot_id}) do
      [{_key, rows}] ->
        rows

      _ ->
        rows = Mangos.GameObjectLootTemplate.query(loot_id) |> Mangos.Repo.all() |> Enum.map(&row/1)
        cache({:gameobject, loot_id}, rows)
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
        rows = Mangos.ReferenceLootTemplate.query(entry) |> Mangos.Repo.all() |> Enum.map(&row/1)
        cache({:reference, entry}, rows)
    end
  end

  defp preload_reference(entry, seen) do
    if MapSet.member?(seen, entry) do
      seen
    else
      rows = Mangos.ReferenceLootTemplate.query(entry) |> Mangos.Repo.all()
      cache({:reference, entry}, Enum.map(rows, &row/1))

      Enum.each(rows, &preload_item/1)

      Enum.reduce(rows, MapSet.put(seen, entry), &preload_nested_reference/2)
    end
  end

  defp preload_nested_reference(%{mincount_or_ref: reference}, seen) when reference < 0 do
    preload_reference(-reference, seen)
  end

  defp preload_nested_reference(_row, seen), do: seen

  defp preload_item(%{item: item}) when item > 0, do: ItemLoader.get_template(item)
  defp preload_item(_row), do: nil

  defp preload_gameobject(loot_id) do
    rows = Mangos.GameObjectLootTemplate.query(loot_id) |> Mangos.Repo.all()
    cache({:gameobject, loot_id}, Enum.map(rows, &row/1))

    Enum.each(rows, &preload_item/1)

    rows
    |> Enum.map(& &1.mincount_or_ref)
    |> Enum.filter(&(&1 < 0))
    |> Enum.reduce(MapSet.new(), fn reference, seen -> preload_reference(-reference, seen) end)
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
