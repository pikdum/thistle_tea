defmodule ThistleTea.Game.World.AuctionStore do
  @moduledoc """
  Commits the auction book, item escrow, player receipt, and mail outbox in
  one ETS insertion. Sharing ItemStore's table makes item custody and market
  settlement atomic and retains both across coordinator restarts.
  """

  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.Change
  alias ThistleTea.Game.Entity.Data.Auction.Delivery
  alias ThistleTea.Game.Entity.Data.Auction.Receipt
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.World.ItemStore

  def book(table \\ ItemStore) do
    case :ets.lookup(table, {:auction, :book}) do
      [{_key, %Book{} = book}] -> book
      [] -> %Book{}
    end
  end

  def item(guid, table \\ ItemStore) do
    case :ets.lookup(table, guid) do
      [{^guid, %Item{} = item}] -> item
      _ -> nil
    end
  end

  def commit(%Change{} = change, receipt \\ nil, table \\ ItemStore) do
    rows = [{{:auction, :book}, change.book} | receipt_rows(receipt)]
    rows = rows ++ escrow_rows(change) ++ Enum.flat_map(change.deliveries, &delivery_rows/1)
    true = :ets.insert(table, rows)
    :ok
  end

  def pending(guid, table \\ ItemStore) do
    case :ets.lookup(table, {:auction, :receipt, guid}) do
      [{_key, %Receipt{} = receipt}] -> receipt
      [] -> nil
    end
  end

  def acknowledge(%Receipt{guid: guid} = receipt, table \\ ItemStore) do
    :ets.delete_object(table, {{:auction, :receipt, guid}, receipt})
    :ok
  end

  def deliveries(table \\ ItemStore) do
    for {_key, %Delivery{} = delivery} <- :ets.match_object(table, {{:auction, :delivery, :_}, :_}),
        do: delivery
  end

  def delivered(%Delivery{key: key} = delivery, table \\ ItemStore) do
    :ets.delete_object(table, {{:auction, :delivery, key}, delivery})
    :ok
  end

  defp receipt_rows(nil), do: []

  defp receipt_rows(%Receipt{guid: guid, changes: changes} = receipt) do
    removed = Enum.map(ChangeSet.destroyed_items(changes), &{&1.object.guid, nil})
    written = Enum.map(ChangeSet.changed_items(changes) ++ ChangeSet.placed_items(changes), &{&1.object.guid, &1})
    [{{:auction, :receipt, guid}, receipt} | removed ++ written]
  end

  defp escrow_rows(%Change{action: :started, auction: auction}), do: [{auction.item.object.guid, auction.item}]
  defp escrow_rows(_change), do: []

  defp delivery_rows(%Delivery{key: key, item: item} = delivery) do
    rows = [{{:auction, :delivery, key}, delivery}]
    if item, do: [{item.object.guid, item} | rows], else: rows
  end
end
