defmodule ThistleTea.Game.World.Loader.ItemDurationVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.World.Loader.Item

  @moduletag :vmangos_db

  describe "get_template/1" do
    test "retains ordinary and real-time lifetimes and conjured flags from the seed" do
      assert %ItemTemplate{duration: 300, flags: 0} = Item.get_template(10_439)
      assert %ItemTemplate{duration: 14_400, flags: 65_536} = Item.get_template(19_807)
      assert %ItemTemplate{duration: 300, flags: 229_378, inventory_type: 21} = Item.get_template(22_736)
    end
  end
end
