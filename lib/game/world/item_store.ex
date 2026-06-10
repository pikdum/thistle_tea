defmodule ThistleTea.Game.World.ItemStore do
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    table =
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, @table_options)
        _table_id -> table
      end

    :ets.insert_new(table, {:counter, 0})
    table
  end

  def create(template_or_entry, opts \\ [])

  def create(%ItemTemplate{} = template, opts) do
    guid = Guid.from_low_guid(:item, next_low_guid())
    item = Item.build(template, guid, opts)
    :ets.insert(__MODULE__, {guid, item})
    item
  end

  def create(entry, opts) when is_integer(entry) do
    case ItemLoader.get_template(entry) do
      %ItemTemplate{} = template -> create(template, opts)
      _ -> nil
    end
  end

  def get(guid) when is_integer(guid) and guid > 0 do
    case :ets.lookup(__MODULE__, guid) do
      [{^guid, %Item{} = item}] -> item
      _ -> nil
    end
  end

  def get(_guid), do: nil

  def put(%Item{object: %{guid: guid}} = item) when is_integer(guid) and guid > 0 do
    :ets.insert(__MODULE__, {guid, item})
    item
  end

  def delete(guid) when is_integer(guid) do
    :ets.delete(__MODULE__, guid)
    :ok
  end

  defp next_low_guid do
    :ets.update_counter(__MODULE__, :counter, 1)
  end
end
