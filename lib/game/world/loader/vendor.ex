defmodule ThistleTea.Game.World.Loader.Vendor do
  @moduledoc """
  ETS cache of direct and template vendor inventories, including stock terms.
  """
  import Ecto.Query

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
    direct = Mangos.Repo.all(from(row in Mangos.NpcVendor, order_by: [row.slot, row.item]))
    shared = Mangos.Repo.all(from(row in Mangos.NpcVendorTemplate, order_by: [row.slot, row.item]))
    conditions = (direct ++ shared) |> Enum.map(& &1.condition_id) |> ConditionLoader.load_by_ids()
    templates = Enum.group_by(shared, & &1.entry)

    vendors =
      Mangos.Repo.all(
        from(creature in Mangos.CreatureTemplate,
          where: creature.vendor_template_id > 0,
          select: {creature.entry, creature.vendor_template_id}
        )
      )

    rows =
      Enum.reduce(vendors, Enum.group_by(direct, & &1.entry), fn {entry, template_id}, rows ->
        Map.update(rows, entry, Map.get(templates, template_id, []), &(&1 ++ Map.get(templates, template_id, [])))
      end)

    Enum.each(rows, fn {entry, entry_rows} -> :ets.insert(__MODULE__, {entry, build_items(entry_rows, conditions)}) end)

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
      _not_preloaded -> load_rows(direct_rows(entry) ++ template_rows(entry), entry)
    end
  end

  defp direct_rows(entry), do: entry |> Mangos.NpcVendor.query() |> Mangos.Repo.all()

  defp template_rows(entry) do
    case Mangos.Repo.get(Mangos.CreatureTemplate, entry) do
      %Mangos.CreatureTemplate{vendor_template_id: id} when id > 0 ->
        Mangos.Repo.all(from(row in Mangos.NpcVendorTemplate, where: row.entry == ^id, order_by: [row.slot, row.item]))

      _ ->
        []
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
    |> Enum.uniq_by(& &1.item)
    |> Enum.reject(&(&1.maxcount > 0 and &1.incrtime <= 0))
    |> Enum.map(fn row ->
      {ItemLoader.get_template(row.item), row}
    end)
    |> Enum.reject(fn {template, _row} -> is_nil(template) end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{%ItemTemplate{} = template, row}, index} ->
      %VendorItem{
        index: index,
        template: template,
        max_count: row.maxcount,
        restock_seconds: row.incrtime,
        flags: row.itemflags,
        condition: Map.get(conditions, row.condition_id)
      }
    end)
  end
end
