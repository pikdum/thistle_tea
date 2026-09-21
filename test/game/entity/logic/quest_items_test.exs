defmodule ThistleTea.Game.Entity.Logic.QuestItemsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.QuestItems

  describe "missing_source_count/3" do
    test "counts carried and banked stacks and grants only the deficit" do
      template = %ItemTemplate{entry: 10, stackable: 20}
      first = Item.build(template, 1, stack_count: 2)
      banked = Item.build(template, 2, stack_count: 3)
      player = %Player{inv1: 1, bank1: 2}
      lookup = lookup([first, banked])
      quest = %Quest{id: 1, src_item_id: 10, src_item_count: 7}
      assert QuestItems.missing_source_count(player, quest, lookup) == 2
      assert QuestItems.missing_source_count(player, %{quest | src_item_count: 2}, lookup) == 0
      assert QuestItems.missing_source_count(%Player{}, %{quest | src_item_count: 0}, lookup) == 1
      assert QuestItems.missing_source_count(player, %Quest{id: 1}, lookup) == 0
    end
  end

  describe "abandon/3" do
    test "removes overlapping source and quest objectives once across carried and bank storage" do
      template = %ItemTemplate{entry: 10, bonding: 4, stackable: 20}
      first = Item.build(template, 1, stack_count: 2)
      banked = Item.build(template, 2, stack_count: 3)
      ordinary = Item.build(%ItemTemplate{entry: 20}, 3)
      quest = %Quest{id: 1, src_item_id: 10, src_item_count: 3, required_items: [{0, 10, 2}, {1, 20, 1}]}
      player = %Player{inv1: 1, bank1: 2, inv2: 3}
      lookup = lookup([first, banked, ordinary])
      {batch, []} = QuestItems.abandon(player, quest, lookup)
      assert {:ok, changes} = Inventory.plan(batch, lookup)
      assert Enum.map(ChangeSet.destroyed_items(changes), & &1.object.guid) == [1, 2]
      assert changes.player.inv2 == 3
      assert changes.player.inv1 == 0
      assert changes.player.bank1 == 0
    end

    test "preserves a source item that starts the same quest" do
      item = Item.build(%ItemTemplate{entry: 10, start_quest: 7}, 1)
      quest = %Quest{id: 7, src_item_id: 10}
      {batch, []} = QuestItems.abandon(%Player{inv1: 1}, quest, lookup([item]))
      assert Batch.removals(batch) == []
    end

    test "restores the original starter only when the full source count can be consumed" do
      starter = %ItemTemplate{entry: 20, start_quest: 7}
      item = Item.build(%ItemTemplate{entry: 10, stackable: 20}, 1, stack_count: 3)
      quest = %Quest{id: 7, src_item_id: 10, src_item_count: 2, start_item_template: starter}
      lookup = lookup([item])
      player = %Player{bank1: 1}
      {batch, [{^starter, 2}]} = QuestItems.abandon(player, quest, lookup)
      assert {:ok, changes} = Inventory.plan(batch, lookup)
      assert ChangeSet.get_item(changes, 1, lookup).item.stack_count == 1
      {batch, []} = QuestItems.abandon(player, %{quest | src_item_count: 4}, lookup)
      assert Batch.removals(batch) == []
    end

    test "consumes protected objective scrolls while ordinary destruction remains forbidden" do
      scroll = Item.build(%ItemTemplate{entry: 10, flags: 0x20, bonding: 4}, 1)
      lookup = lookup([scroll])
      player = %Player{inv1: 1}
      quest = %Quest{id: 7, required_items: [{0, 10, 1}]}
      {batch, []} = QuestItems.abandon(player, quest, lookup)
      assert {:ok, changes} = Inventory.plan(batch, lookup)
      assert ChangeSet.destroyed_items(changes) == [scroll]
      assert {:error, :cant_drop_soulbound} = Inventory.plan(Batch.remove_item(Batch.new(player), 1, 1), lookup)
    end

    test "rejects consuming a bag with contents before committing any removals" do
      bag = Item.build(%ItemTemplate{entry: 10, class: 1, inventory_type: 18, container_slots: 4}, 1)
      bag = %{bag | container: %{bag.container | slot_1: 2}}
      inside = Item.build(%ItemTemplate{entry: 20}, 2)
      objective = Item.build(%ItemTemplate{entry: 30, bonding: 4}, 3)
      player = %Player{bag1: 1, inv1: 3}
      lookup = lookup([bag, inside, objective])
      quest = %Quest{id: 7, src_item_id: 10, required_items: [{0, 30, 1}]}
      {batch, []} = QuestItems.abandon(player, quest, lookup)
      assert {:error, :can_only_do_with_empty_bags} = Inventory.plan(batch, lookup)
      assert lookup.(1) == bag
      assert lookup.(3) == objective
    end
  end

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end
end
