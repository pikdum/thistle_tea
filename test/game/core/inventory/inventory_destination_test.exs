defmodule ThistleTea.Game.Core.Inventory.InventoryDestinationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Item.Proficiency

  setup [:inventory]

  describe "plan/3" do
    test "keeps an explicit empty slot ahead of existing partial stacks", context do
      %{stack: stack, incoming: incoming} = context
      player = %Player{inv1: stack.object.guid}
      batch = player |> Batch.new() |> Batch.add(incoming, {255, 30})

      assert {:ok, changes} = Inventory.plan(batch, lookup([stack]))
      assert changes.player.inv8 == incoming.object.guid
      assert changes.player.inv1 == stack.object.guid
      assert ChangeSet.changed_items(changes) == []
      assert [%{item: %{stack_count: 5, contained: 1}}] = ChangeSet.placed_items(changes)
    end

    test "fills the selected stack, then the same bag, then carried storage", context do
      %{stack: stack, incoming: incoming, bag: bag} = context
      bag = %{bag | container: %{bag.container | slot_2: stack.object.guid}}
      player = %Player{bag1: bag.object.guid}
      get_item = lookup([bag, stack])
      batch = player |> Batch.new() |> Batch.add(incoming, {19, 1})

      assert {:ok, changes} = Inventory.plan(batch, get_item)
      assert ChangeSet.get_item(changes, stack.object.guid, get_item).item.stack_count == 10
      assert ChangeSet.get_item(changes, bag.object.guid, get_item).container.slot_1 == incoming.object.guid
      assert [%{item: %{stack_count: 3, contained: bag_guid}}] = ChangeSet.placed_items(changes)
      assert bag_guid == bag.object.guid

      filler = Item.build(%ItemTemplate{entry: 999}, 104, owner: 1)
      bag = %{bag | container: %{bag.container | slot_1: filler.object.guid}}
      assert {:ok, changes} = Inventory.plan(batch, lookup([bag, stack, filler]))
      assert changes.player.inv1 == incoming.object.guid
      assert [%{item: %{stack_count: 3, contained: 1}}] = ChangeSet.placed_items(changes)
    end

    test "a preferred backpack spills into another bag", context do
      %{incoming: incoming, bag: bag} = context
      filler = Item.build(%ItemTemplate{entry: 999}, 104, owner: 1)
      player = full_backpack(%Player{bag1: bag.object.guid}, filler)
      batch = player |> Batch.new() |> Batch.add(incoming, {:bag, 255})

      assert {:ok, changes} = Inventory.plan(batch, lookup([bag, filler]))
      assert [%{position: {19, 0}}] = changes.placements
    end

    test "rejects occupied, full, missing and incompatible destinations", context do
      %{stack: stack, incoming: incoming, bag: bag} = context
      other = Item.build(%ItemTemplate{entry: 999}, 104, owner: 1)
      full = %{stack | item: %{stack.item | stack_count: 10}}

      for occupied <- [other, full] do
        batch = %Player{inv1: occupied.object.guid} |> Batch.new() |> Batch.add(incoming, {255, 23})
        assert {:error, :item_cant_stack} = Inventory.plan(batch, lookup([occupied]))
      end

      bag = %{bag | internal: %{bag.internal | template: %{Item.template(bag) | bag_family: 32}}}
      player = %Player{bag1: bag.object.guid}

      for destination <- [{19, 2}, {20, 0}, {:bag, 20}, {19, 0}, {:bag, 19}] do
        batch = player |> Batch.new() |> Batch.add(incoming, destination)
        assert {:error, :item_doesnt_go_to_slot} = Inventory.plan(batch, lookup([bag]))
      end
    end

    test "a later failure discards merges and honors banked unique limits", context do
      %{stack: stack, incoming: incoming, bag: bag} = context
      unique = Item.build(%ItemTemplate{entry: 999, max_count: 1}, 104, owner: 1)
      duplicate = %{unique | object: %{unique.object | guid: 105}}
      bag = %{bag | container: %{bag.container | slot_1: stack.object.guid}}
      player = %Player{bag1: bag.object.guid, bank1: unique.object.guid}

      batch = player |> Batch.new() |> Batch.add(incoming, {19, 0}) |> Batch.add(duplicate, {255, 30})
      assert {:error, :cant_carry_more_of_this} = Inventory.plan(batch, lookup([bag, stack, unique]))
      assert stack.item.stack_count == 8
      assert bag.container.slot_2 == 0
    end

    test "equipping a two-handed purchase stores the offhand or fails atomically" do
      sword = Item.build(%ItemTemplate{entry: 900, inventory_type: 17, bonding: 2}, 100, owner: 1)
      shield = Item.build(%ItemTemplate{entry: 901, inventory_type: 14}, 101, owner: 1)
      player = %Player{offhand: shield.object.guid}
      batch = player |> Batch.new() |> Batch.add(sword, {255, 15})
      opts = [unit: %Unit{class: 1, race: 1, level: 60}, proficiency: Proficiency.all()]

      assert {:ok, changes} = Inventory.plan(batch, lookup([shield]), opts)
      assert changes.player.mainhand == sword.object.guid
      assert changes.player.offhand == 0
      assert changes.player.inv1 == shield.object.guid
      assert [%{item: %{flags: 1}}] = ChangeSet.placed_items(changes)

      filler = Item.build(%ItemTemplate{entry: 999}, 104, owner: 1)
      batch = player |> full_backpack(filler) |> Batch.new() |> Batch.add(sword, {255, 15})
      assert {:error, :cant_equip_with_twohanded} = Inventory.plan(batch, lookup([shield, filler]), opts)
      assert player.offhand == shield.object.guid
    end
  end

  defp inventory(_context) do
    template = %ItemTemplate{entry: 900, stackable: 10}

    %{
      stack: Item.build(template, 100, owner: 1, stack_count: 8),
      incoming: Item.build(template, 101, owner: 1, stack_count: 5),
      bag: Item.build(%ItemTemplate{entry: 901, class: 1, inventory_type: 18, container_slots: 2}, 102, owner: 1)
    }
  end

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end

  defp full_backpack(player, filler) do
    fields = Map.new(1..16, &{String.to_atom("inv#{&1}"), filler.object.guid})
    struct!(player, fields)
  end
end
