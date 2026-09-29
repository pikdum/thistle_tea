defmodule ThistleTea.Game.Core.Vendor.VendorStock do
  @moduledoc """
  A merchant's depleted stock and the interval selected on its last purchase,
  with pure depletion and lazy replenishment. Full and unlimited inventory
  requires no stock record. Purchases reset the replenishment interval; elapsed
  intervals restore purchase-sized bundles.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Vendor.VendorItem
  alias ThistleTea.Game.Core.Vendor.VendorStock

  @enforce_keys [:count, :last_increment_at, :restock_ms]
  defstruct @enforce_keys

  defmodule Receipt do
    @moduledoc """
    A committed merchant purchase awaiting projection by the player owner.
    Stock, item rows, and this recovery receipt are written together.
    """

    @enforce_keys [:id, :guid, :changes, :old_counts, :vendor_guid, :vendor_item, :count, :available, :position]
    defstruct @enforce_keys
  end

  def current(_stock, %VendorItem{max_count: maximum}, _now) when maximum <= 0, do: {0xFFFFFFFF, nil}
  def current(nil, %VendorItem{max_count: maximum}, _now), do: {maximum, nil}

  def current(%VendorStock{} = stock, %VendorItem{} = item, now) do
    intervals = div(max(now - stock.last_increment_at, 0), stock.restock_ms)
    count = min(stock.count + intervals * max(item.template.buy_count, 1), item.max_count)

    cond do
      count >= item.max_count -> {item.max_count, nil}
      intervals > 0 -> {count, %{stock | count: count, last_increment_at: now}}
      true -> {count, stock}
    end
  end

  def purchase(stock, %VendorItem{} = item, count, now, restock_ms) when is_integer(count) and count > 0 do
    {available, stock} = current(stock, item, now)

    cond do
      item.max_count <= 0 ->
        {:ok, 0xFFFFFFFF, nil}

      count > available ->
        {:error, :item_already_sold, stock}

      true ->
        available = available - count
        stock = %VendorStock{count: available, last_increment_at: now, restock_ms: max(restock_ms, 1_000)}
        {:ok, available, stock}
    end
  end

  def restock_delay(%VendorItem{} = item, random_percent, population) do
    seconds = max(item.restock_seconds, 1)
    seconds = if (item.flags &&& 1) == 0, do: seconds, else: div(seconds * random_percent, 100)
    seconds = if (item.flags &&& 2) != 0 and population > 2_500, do: div(seconds * 2_500, population), else: seconds
    max(seconds, 1) * 1_000
  end
end
