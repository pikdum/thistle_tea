defmodule ThistleTea.Game.World.Loader.VendorVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.World.Loader.Vendor

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "preserves explicit slots, finite stock intervals and restock flags" do
      assert :ok = Vendor.load_all()
      assert [11_444, 11_325, 13_483, 15_759] == Enum.map(Vendor.items(9499), & &1.template.entry)
      assert %VendorItem{index: 2, max_count: 10, restock_seconds: 60, flags: 0} = Vendor.find_item(9499, 11_325)
      assert %VendorItem{max_count: 1, restock_seconds: 3_600, flags: 3} = Vendor.find_item(9499, 15_759)
    end

    test "combines creature-specific and template inventories with cached conditions" do
      assert :ok = Vendor.load_all()
      items = Vendor.items(1464)
      entries = Enum.map(items, & &1.template.entry)
      assert 117 in entries
      assert Enum.all?([21_815, 21_829, 21_833], &(&1 in entries))
      assert length(entries) == length(Enum.uniq(entries))
      assert Enum.map(items, & &1.index) == Enum.to_list(1..length(items))
    end
  end
end
