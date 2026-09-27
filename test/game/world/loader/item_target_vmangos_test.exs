defmodule ThistleTea.Game.World.Loader.ItemTargetVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.ItemTarget

  @moduletag :vmangos_db

  setup do
    saved = :ets.tab2list(ItemTarget)
    ItemTarget.load_all()

    on_exit(fn ->
      :ets.delete_all_objects(ItemTarget)
      :ets.insert(ItemTarget, saved)
    end)
  end

  describe "load_all/0" do
    test "preloads living targets, dead targets, and alternative creature entries" do
      assert ItemTarget.get(9328) == [{7977, true}]
      assert ItemTarget.get(8149) == [{7318, false}]
      assert ItemTarget.get(15_908) == [{1196, true}]
      assert ItemTarget.get(9618) == [{2927, false}, {2928, false}, {2929, false}, {7808, false}]
      assert ItemTarget.get(1599) == []
      assert Enum.sum(Enum.map(:ets.tab2list(ItemTarget), fn {_entry, targets} -> length(targets) end)) == 37
    end
  end
end
