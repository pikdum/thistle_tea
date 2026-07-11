defmodule ThistleTea.Game.Entity.Data.ItemTest do
  use ExUnit.Case, async: true

  import Bitwise

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

  describe "temporary enchantments" do
    test "stores the enchantment fields and visible enchant id" do
      item = Item.build(%ItemTemplate{entry: 6256}, 1)
      item = Item.put_temporary_enchantment(item, 263, 600_000, 0, 700_000, :token)

      assert Item.temporary_enchantment(item) == %{id: 263, expires_at: 700_000, charges: 0, token: :token}
      assert Item.visible_value(item) == (6256 ||| 263 <<< 64)
      assert (item.item.enchantment >>> 96 &&& 0xFFFFFFFF) == 263
      assert (item.item.enchantment >>> 128 &&& 0xFFFFFFFF) == 600_000
    end

    test "refreshes remaining duration and clears expired enchantments" do
      item = Item.build(%ItemTemplate{entry: 6256}, 1)
      item = Item.put_temporary_enchantment(item, 263, 600_000, 0, 700_000, :token)

      {active, enchantment} = Item.refresh_temporary_enchantment(item, 200_000)
      assert enchantment.token == :token
      assert (active.item.enchantment >>> 128 &&& 0xFFFFFFFF) == 500_000

      {expired, nil} = Item.refresh_temporary_enchantment(active, 700_000)
      assert Item.temporary_enchantment(expired) == nil
      assert Item.visible_value(expired) == 6256
    end
  end
end
