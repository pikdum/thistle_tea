defmodule ThistleTea.Game.World.Loader.Vendor do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
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
    items =
      Mangos.NpcVendor.query(entry)
      |> Mangos.Repo.all()
      |> Enum.map(fn row -> {ItemLoader.get_template(row.item), row.maxcount} end)
      |> Enum.reject(fn {template, _maxcount} -> is_nil(template) end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{%ItemTemplate{} = template, maxcount}, index} ->
        %{index: index, template: template, max_count: maxcount}
      end)

    :ets.insert(__MODULE__, {entry, items})
    items
  end
end
