defmodule ThistleTea.Game.Entity.Data.ItemTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  describe "build/3" do
    test "populates object and item components from template" do
      template = %ItemTemplate{entry: 25, flags: 4, duration: 0, max_durability: 20}
      item = Item.build(template, 0x4000_0000_0000_002A, owner: 99)

      assert item.object.guid == 0x4000_0000_0000_002A
      assert item.object.entry == 25
      assert item.object.scale_x == 1.0
      assert item.item.owner == 99
      assert item.item.contained == 99
      assert item.item.stack_count == 1
      assert item.item.flags == 4
      assert item.item.durability == 20
      assert item.item.max_durability == 20
      assert Item.template(item) == template
    end

    test "defaults owner to zero and accepts stack count" do
      template = %ItemTemplate{entry: 25}
      item = Item.build(template, 1, stack_count: 5)

      assert item.item.owner == 0
      assert item.item.stack_count == 5
    end
  end
end
