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
      assert item.item.flags == 0
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

    test "binds pickup and quest items when their instances are created" do
      for bonding <- [1, 4] do
        item = Item.build(%ItemTemplate{entry: 25, bonding: bonding, flags: 4}, 1, owner: 99)
        assert item.item.flags == 1
      end

      for bonding <- [0, 2, 3] do
        item = Item.build(%ItemTemplate{entry: 25, bonding: bonding, flags: 4}, 1, owner: 99)
        assert item.item.flags == 0
      end
    end
  end

  describe "bind_on_equip/1" do
    test "binds equipment without changing other instance flags" do
      for bonding <- [1, 2, 4] do
        item = Item.build(%ItemTemplate{entry: 1, bonding: bonding, flags: 4}, 1)
        item = Item.unlock(item)
        bound = Item.bind_on_equip(item)
        assert bound.item.flags == 5
        assert Item.bind_on_equip(bound) == bound
      end
    end

    test "leaves unbound and bind-on-use items alone" do
      for bonding <- [0, 3] do
        item = Item.build(%ItemTemplate{entry: 1, bonding: bonding}, 1)
        assert Item.bind_on_equip(item) == item
      end
    end
  end

  describe "spend_enchantment_charge/2" do
    test "spends charges without resetting time and clears only the exhausted slot" do
      item = Item.build(%ItemTemplate{entry: 25}, 1)
      item = item |> Item.put_permanent_enchantment(41) |> Item.put_temporary_enchantment(323, 1000, 2, 1000, :token)
      charged = Item.spend_enchantment_charge(item, :token)
      assert Item.temporary_enchantment(charged) == %{id: 323, expires_at: 1000, charges: 1, token: :token}
      assert (charged.item.enchantment >>> 160 &&& 0xFFFFFFFF) == 1
      depleted = Item.spend_enchantment_charge(charged, :token)
      assert Item.temporary_enchantment(depleted) == nil
      assert Item.active_enchantments(depleted, 0) == [{0, 41}]
      assert Item.visible_value(depleted) == (25 ||| 41 <<< 32)
    end

    test "zero means unlimited and stale procs cannot spend replacement charges" do
      item = Item.build(%ItemTemplate{entry: 25}, 1)
      unlimited = Item.put_temporary_enchantment(item, 283, 1000, 0, 1000, :token)
      assert Item.spend_enchantment_charge(unlimited, :token) == unlimited
      replacement = Item.put_temporary_enchantment(item, 323, 1000, 40, 1000, :new)
      assert Item.spend_enchantment_charge(replacement, :token) == replacement
      assert Item.spend_enchantment_charge(item, :token) == item
    end
  end

  describe "refresh_temporary_enchantment/2" do
    test "permanent and temporary slots coexist through refresh and expiry" do
      item = Item.build(%ItemTemplate{entry: 25}, 1)
      item = item |> Item.put_permanent_enchantment(41) |> Item.put_temporary_enchantment(263, 1000, 0, 1000, :token)
      assert Item.active_enchantments(item, 0) == [{0, 41}, {1, 263}]
      replaced = Item.put_permanent_enchantment(item, 1883)
      assert Item.active_enchantments(replaced, 0) == [{0, 1883}, {1, 263}]
      {expired, nil} = Item.refresh_temporary_enchantment(replaced, 1000)
      assert Item.active_enchantments(expired, 1000) == [{0, 1883}]
      assert Item.visible_entry(Item.visible_value(expired)) == 25
    end

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
