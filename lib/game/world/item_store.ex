defmodule ThistleTea.Game.World.ItemStore do
  @moduledoc """
  ETS store of live item instances by guid — the runtime home of items, which
  deliberately never enter visibility tracking.
  """
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Trade.Exchange
  alias ThistleTea.Game.Entity.Data.Trade.Receipt
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
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
    template
    |> prepare(opts)
    |> put()
  end

  def create(entry, opts) when is_integer(entry) do
    {get_template, opts} = Keyword.pop(opts, :get_template, &ItemLoader.get_template/1)

    case get_template.(entry) do
      %ItemTemplate{} = template -> create(template, opts)
      _ -> nil
    end
  end

  def prepare(template_or_entry, opts \\ [])

  def prepare(%ItemTemplate{} = template, opts) do
    guid = Guid.from_low_guid(:item, next_low_guid())
    Item.build(template, guid, opts)
  end

  def prepare(entry, opts) when is_integer(entry) do
    {get_template, opts} = Keyword.pop(opts, :get_template, &ItemLoader.get_template/1)

    case get_template.(entry) do
      %ItemTemplate{} = template -> prepare(template, opts)
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

  def commit_trade(%Exchange{} = exchange, old_counts) do
    receipts =
      Enum.map(exchange.changes, fn {guid, changes} ->
        receipt = %Receipt{
          id: exchange.id,
          guid: guid,
          changes: changes,
          outgoing: Map.fetch!(exchange.outgoing, guid),
          old_counts: Map.fetch!(old_counts, guid),
          cast: Map.get(exchange.casts, guid),
          committed_at: exchange.committed_at
        }

        {{:trade_pending, guid}, receipt}
      end)

    rows =
      Enum.flat_map(exchange.changes, fn {_guid, changes} ->
        removed = Enum.map(ChangeSet.destroyed_items(changes), &{&1.object.guid, nil})
        written = Enum.map(ChangeSet.changed_items(changes) ++ ChangeSet.placed_items(changes), &{&1.object.guid, &1})
        removed ++ written
      end)

    true = :ets.insert(__MODULE__, rows ++ receipts)
    :ok
  end

  def pending_trade(guid) do
    case :ets.lookup(__MODULE__, {:trade_pending, guid}) do
      [{_key, %Receipt{} = receipt}] -> receipt
      _ -> nil
    end
  end

  def acknowledge_trade(%Receipt{guid: guid} = receipt) do
    :ets.delete_object(__MODULE__, {{:trade_pending, guid}, receipt})
    :ok
  end

  defp next_low_guid do
    :ets.update_counter(__MODULE__, :counter, 1)
  end
end
