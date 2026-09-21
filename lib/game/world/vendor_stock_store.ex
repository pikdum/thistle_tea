defmodule ThistleTea.Game.World.VendorStockStore do
  @moduledoc """
  Runtime merchant stock and purchase receipts share ItemStore's ETS table.
  One insertion commits stock, inventory rows, money in the receipt, and its
  recovery marker, including across a coordinator restart.
  """

  alias ThistleTea.Game.Entity.Data.VendorStock.Receipt
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.World.ItemStore

  def stock(key, table \\ ItemStore) do
    case :ets.lookup(table, {:vendor_stock, key}) do
      [{_key, stock}] -> stock
      [] -> nil
    end
  end

  def put(key, nil, table), do: :ets.delete(table, {:vendor_stock, key})
  def put(key, stock, table), do: :ets.insert(table, {{:vendor_stock, key}, stock})

  def commit(key, stock, %Receipt{} = receipt, table \\ ItemStore) do
    changes = receipt.changes
    removed = Enum.map(ChangeSet.destroyed_items(changes), &{&1.object.guid, nil})
    written = Enum.map(ChangeSet.changed_items(changes) ++ ChangeSet.placed_items(changes), &{&1.object.guid, &1})
    rows = [{{:vendor_stock, key}, stock}, {{:vendor_purchase, receipt.guid}, receipt} | removed ++ written]
    true = :ets.insert(table, rows)
    if is_nil(stock), do: :ets.delete(table, {:vendor_stock, key})
    :ok
  end

  def pending(guid, table \\ ItemStore) do
    case :ets.lookup(table, {:vendor_purchase, guid}) do
      [{_key, %Receipt{} = receipt}] -> receipt
      [] -> nil
    end
  end

  def acknowledge(%Receipt{} = receipt, table \\ ItemStore) do
    :ets.delete_object(table, {{:vendor_purchase, receipt.guid}, receipt})
    :ok
  end

  def clear_world(world, table \\ ItemStore) do
    :ets.match_delete(table, {{:vendor_stock, {world, :_, :_}}, :_})
    :ok
  end
end
