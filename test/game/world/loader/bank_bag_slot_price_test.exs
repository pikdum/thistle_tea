defmodule ThistleTea.Game.World.Loader.BankBagSlotPriceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.BankBagSlotPrice

  @moduletag :dbc_db

  test "loads the six build 5875 purchase prices" do
    table = :bank_bag_slot_price_test
    BankBagSlotPrice.init(table)
    BankBagSlotPrice.load_all(table)

    assert Enum.map(1..6, &BankBagSlotPrice.cost(&1, table)) ==
             [1_000, 10_000, 100_000, 250_000, 500_000, 1_000_000]

    assert BankBagSlotPrice.cost(7, table) == nil
  end
end
