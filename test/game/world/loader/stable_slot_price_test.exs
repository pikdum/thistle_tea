defmodule ThistleTea.Game.World.Loader.StableSlotPriceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.StableSlotPrice

  @moduletag :dbc_db

  describe "cost/1" do
    test "loads both vanilla stable prices" do
      StableSlotPrice.load_all()
      assert StableSlotPrice.cost(1) == 500
      assert StableSlotPrice.cost(2) == 50_000
      assert StableSlotPrice.cost(3) == nil
    end
  end
end
