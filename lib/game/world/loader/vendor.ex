defmodule ThistleTea.Game.World.Loader.Vendor do
  @moduledoc """
  ETS cache of vendor inventories from Mangos `npc_vendor` rows.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.VendorItem
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
    rows = Mangos.Repo.all(Mangos.NpcVendor)
    conditions = rows |> Enum.map(& &1.condition_id) |> ConditionLoader.load_by_ids()

    rows
    |> Enum.group_by(& &1.entry)
    |> Enum.each(fn {entry, entry_rows} -> :ets.insert(__MODULE__, {entry, build_items(entry_rows, conditions)}) end)

    :ets.insert(__MODULE__, {:loaded, true})
    :ok
  end

  def items(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, items}] -> items
      _ -> load(entry)
    end
  end

  def items(_entry), do: []

  def find_item(entry, item_id) do
    entry
    |> items()
    |> Enum.find(fn vendor_item -> vendor_item.template.entry == item_id end)
  end

  defp load(entry) do
    case :ets.lookup(__MODULE__, :loaded) do
      [{:loaded, true}] -> []
      _not_preloaded -> entry |> Mangos.NpcVendor.query() |> Mangos.Repo.all() |> load_rows(entry)
    end
  end

  defp load_rows(rows, entry) do
    conditions =
      rows
      |> Enum.map(& &1.condition_id)
      |> ConditionLoader.load_by_ids()

    items = build_items(rows, conditions)

    :ets.insert(__MODULE__, {entry, items})
    items
  end

  defp build_items(rows, conditions) do
    rows
    |> Enum.map(fn row ->
      {ItemLoader.get_template(row.item), row.maxcount, Map.get(conditions, row.condition_id)}
    end)
    |> Enum.reject(fn {template, _maxcount, _condition} -> is_nil(template) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{%ItemTemplate{} = template, maxcount, condition}, index} ->
      %VendorItem{index: index, template: template, max_count: maxcount, condition: condition}
    end)
  end
end
