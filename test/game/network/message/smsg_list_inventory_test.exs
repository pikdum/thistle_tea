defmodule ThistleTea.Game.Network.Message.SmsgListInventoryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Network.Message.SmsgListInventory

  describe "to_binary/1" do
    test "encodes a boundary-supplied discounted price" do
      template = %ItemTemplate{
        entry: 1_234,
        display_id: 567,
        buy_price: 100,
        max_durability: 20,
        buy_count: 2
      }

      message = %SmsgListInventory{
        vendor_guid: 42,
        items: [%{index: 1, template: template, max_count: 0, price: 90}]
      }

      assert SmsgListInventory.to_binary(message) ==
               <<42::little-size(64), 1, 1::little-size(32), 1_234::little-size(32), 567::little-size(32),
                 0xFFFFFFFF::little-size(32), 90::little-size(32), 20::little-size(32), 2::little-size(32)>>
    end
  end
end
