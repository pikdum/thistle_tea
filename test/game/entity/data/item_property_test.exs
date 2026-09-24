defmodule ThistleTea.Game.Entity.Data.ItemPropertyTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.ItemTransformation

  setup [:build_item]

  describe "build/3" do
    test "sets the client property id and separate enchantment slots", %{item: item, property: property} do
      assert Item.random_property(item) == property
      assert item.item.random_properties_id == 1182
      assert item.item.property_seed == 0
      assert (item.item.enchantment >>> 288 &&& 0xFFFFFFFF) == 72
      assert (item.item.enchantment >>> 384 &&& 0xFFFFFFFF) == 69
      assert (item.item.enchantment >>> 480 &&& 0xFFFFFFFF) == 0
      assert Item.active_enchantments(item, 0) == [{3, 72}, {4, 69}]
      assert Item.name(item) == "Test Mace of the Bear"
    end
  end

  describe "active_enchantments/2" do
    test "retains property bonuses when applied enchants change and expire", %{item: item} do
      enchanted =
        item |> Item.put_permanent_enchantment(41) |> Item.put_temporary_enchantment(263, 1000, 0, 1000, :token)

      assert Item.active_enchantments(enchanted, 0) == [{0, 41}, {1, 263}, {3, 72}, {4, 69}]
      replaced = Item.put_permanent_enchantment(enchanted, 1883)
      {expired, nil} = Item.refresh_temporary_enchantment(replaced, 1000)
      assert Item.active_enchantments(expired, 1000) == [{0, 1883}, {3, 72}, {4, 69}]
      assert expired.item.random_properties_id == 1182
    end
  end

  describe "sync_visible_item/3" do
    test "projects the suffix for inspection and clears it on unequip", %{item: item} do
      equipped = Inventory.equip(%Player{}, 15, item)
      assert equipped.visible_item_16_properties == 1182
      assert equipped.visible_item_16_0 == 100
      cleared = Inventory.sync_visible_item(equipped, 15, nil)
      assert cleared.visible_item_16_properties == 0
      assert cleared.visible_item_16_0 == 0
    end
  end

  describe "wrap/3" do
    test "hides the suffix on gifts and restores the same property", %{item: item} do
      wrapped = Item.wrap(item, %ItemTemplate{entry: 200, name: "Gift"}, 5)
      assert Item.name(wrapped) == "Gift"
      assert {:ok, restored} = Item.unwrap(wrapped)
      assert Item.name(restored) == Item.name(item)
      assert Item.random_property(restored) == Item.random_property(item)
      assert restored.item.enchantment == item.item.enchantment
    end
  end

  describe "prepare/3" do
    test "item transformations retain the replacement's property", %{item: item} do
      replacement =
        Item.build(%ItemTemplate{entry: 101}, 11, random_property: %ItemProperty{id: 19, enchantments: [72]})

      transformed = ItemTransformation.prepare(replacement, Item.put_permanent_enchantment(item, 41), 0)
      assert transformed.item.random_properties_id == 19
      assert Item.active_enchantments(transformed, 0) == [{0, 41}, {3, 72}]
    end
  end

  defp build_item(_context) do
    property = %ItemProperty{id: 1182, suffix: "of the Bear", enchantments: [72, 69, 0]}
    item = Item.build(%ItemTemplate{entry: 100, name: "Test Mace"}, 10, random_property: property)
    %{item: item, property: property}
  end
end
