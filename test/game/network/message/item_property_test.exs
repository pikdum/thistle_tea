defmodule ThistleTea.Game.Network.Message.ItemPropertyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Network.Message

  describe "to_binary/1" do
    test "loot windows and item receipts encode the same property" do
      property = %ItemProperty{id: 1182}
      item = %Loot.Item{slot: 2, item_id: 1608, count: 1, display_id: 123, random_property: property}
      response = %Message.SmsgLootResponse{guid: 10, loot: %Loot{items: [item]}}

      assert <<10::little-64, 1, 0::little-32, 1, 2, 1608::little-32, 1::little-32, 123::little-32, 0::little-32,
               1182::little-32, 0>> == Message.SmsgLootResponse.to_binary(response)

      receipt = %Message.SmsgItemPushResult{
        player_guid: 5,
        item_id: 1608,
        bag_slot: 255,
        item_slot: 23,
        random_property_id: 1182
      }

      assert <<5::little-64, 0::little-32, 0::little-32, 1::little-32, 255, 23::little-32, 1608::little-32,
               0::little-32, 1182::little-32, 1::little-32>> == Message.SmsgItemPushResult.to_binary(receipt)
    end

    test "group roll packets keep vanilla property field ordering" do
      start = %Message.SmsgLootStartRoll{loot_guid: 10, slot: 2, item_id: 1608, random_prop: 1182}

      assert <<10::little-64, 2::little-32, 1608::little-32, 0::little-32, 1182::little-32, 60_000::little-32>> ==
               Message.SmsgLootStartRoll.to_binary(start)

      won = %Message.SmsgLootRollWon{
        loot_guid: 10,
        slot: 2,
        item_id: 1608,
        random_prop: 1182,
        winner_guid: 5,
        roll_number: 99,
        roll_type: 1
      }

      assert <<10::little-64, 2::little-32, 1608::little-32, 0::little-32, 1182::little-32, 5::little-64, 99, 1>> ==
               Message.SmsgLootRollWon.to_binary(won)

      passed = %Message.SmsgLootAllPassed{loot_guid: 10, slot: 2, item_id: 1608, random_prop: 1182}

      assert <<10::little-64, 2::little-32, 1608::little-32, 1182::little-32, 0::little-32>> ==
               Message.SmsgLootAllPassed.to_binary(passed)
    end
  end
end
