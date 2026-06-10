defmodule ThistleTea.Game.World.ItemStoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.ItemStore

  setup [:build_template]

  defp build_template(_context) do
    {:ok, template: %ItemTemplate{entry: 4321, max_durability: 30}}
  end

  describe "create/2" do
    test "allocates unique item guids", %{template: template} do
      item1 = ItemStore.create(template, owner: 1)
      item2 = ItemStore.create(template, owner: 1)

      assert item1.object.guid != item2.object.guid
      assert Guid.high_guid(item1.object.guid) == Guid.high_guid(:item)
      assert Guid.entity_type(item1.object.guid) == :item
    end

    test "stores the created item", %{template: template} do
      item = ItemStore.create(template, owner: 42)

      assert ItemStore.get(item.object.guid) == item
      assert item.item.owner == 42
    end
  end

  describe "get/1" do
    test "returns nil for unknown or invalid guids" do
      assert ItemStore.get(0xDEAD_BEEF_0000_0000) == nil
      assert ItemStore.get(nil) == nil
      assert ItemStore.get(0) == nil
    end
  end

  describe "put/1" do
    test "replaces a stored item", %{template: template} do
      item = ItemStore.create(template)
      updated = %{item | item: %{item.item | stack_count: 3}}

      assert %Item{} = ItemStore.put(updated)
      assert ItemStore.get(item.object.guid).item.stack_count == 3
    end
  end

  describe "delete/1" do
    test "removes a stored item", %{template: template} do
      item = ItemStore.create(template)

      assert ItemStore.delete(item.object.guid) == :ok
      assert ItemStore.get(item.object.guid) == nil
    end
  end
end
