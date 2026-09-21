defmodule ThistleTea.Game.Entity.Logic.VendorStockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Entity.Logic.VendorStock

  setup [:merchant]

  describe "purchase/5 and current/3" do
    test "shares finite units and rejects an oversubscribed bundle", %{item: item} do
      assert {:ok, 4, stock} = VendorStock.purchase(nil, item, 6, 0, 10_000)
      assert {:error, :item_already_sold, ^stock} = VendorStock.purchase(stock, item, 6, 0, 10_000)
      assert {4, ^stock} = VendorStock.current(stock, item, 9_999)
      assert {7, replenished} = VendorStock.current(stock, item, 10_000)
      assert replenished.last_increment_at == 10_000
      assert {:ok, 1, _stock} = VendorStock.purchase(replenished, item, 6, 10_000, 10_000)
    end

    test "restocks whole bundles, caps at maximum and drops a full record", %{item: item} do
      {:ok, 0, stock} = VendorStock.purchase(nil, item, 10, 100, 10_000)
      assert {9, partial} = VendorStock.current(stock, item, 35_100)
      assert partial.last_increment_at == 35_100
      assert {9, ^partial} = VendorStock.current(partial, item, 45_099)
      assert {10, nil} = VendorStock.current(partial, item, 45_100)
      assert {10, nil} = VendorStock.current(stock, item, 1_000_000)
    end

    test "each purchase resets the selected replenishment interval", %{item: item} do
      {:ok, 7, stock} = VendorStock.purchase(nil, item, 3, 0, 10_000)
      {:ok, 4, stock} = VendorStock.purchase(stock, item, 3, 9_000, 12_000)
      assert {4, ^stock} = VendorStock.current(stock, item, 20_999)
      assert {7, _stock} = VendorStock.current(stock, item, 21_000)
      assert {4, ^stock} = VendorStock.current(stock, item, -1)
    end

    test "unlimited merchandise never retains stock", %{item: item} do
      item = %{item | max_count: 0, restock_seconds: 0}
      assert {:ok, 0xFFFFFFFF, nil} = VendorStock.purchase(nil, item, 900, 0, 0)
      assert {0xFFFFFFFF, nil} = VendorStock.current(nil, item, 99_000)
    end
  end

  describe "restock_delay/3" do
    test "applies seed flags with per-stage whole-second truncation", %{item: item} do
      item = %{item | restock_seconds: 61}
      assert VendorStock.restock_delay(item, 80, 5_000) == 61_000
      assert VendorStock.restock_delay(%{item | flags: 1}, 80, 5_000) == 48_000
      assert VendorStock.restock_delay(%{item | flags: 1}, 120, 5_000) == 73_000
      assert VendorStock.restock_delay(%{item | flags: 2}, 120, 5_000) == 30_000
      assert VendorStock.restock_delay(%{item | flags: 3}, 120, 5_000) == 36_000
      assert VendorStock.restock_delay(%{item | flags: 3}, 100, 2_500) == 61_000
      assert VendorStock.restock_delay(%{item | restock_seconds: 0}, 100, 0) == 1_000
    end
  end

  defp merchant(_context) do
    %{item: %VendorItem{index: 1, template: %ItemTemplate{entry: 25, buy_count: 3}, max_count: 10, restock_seconds: 10}}
  end
end
