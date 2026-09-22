defmodule ThistleTea.Game.Entity.Logic.Inventory.ReplacementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Proficiency

  setup [:items]

  describe "plan/3" do
    test "chained replacements discard intermediate instances", %{original: original, replacement: replacement} do
      final = Item.build(%ItemTemplate{entry: 3}, 100, owner: 1)

      batch =
        %Player{inv1: original.object.guid}
        |> Batch.new()
        |> Batch.replace(original.object.guid, replacement)
        |> Batch.replace(replacement.object.guid, final)

      assert {:ok, changes} = Inventory.plan(batch, lookup([original]))
      assert [^final] = ChangeSet.placed_items(changes)
      assert [original, replacement] == ChangeSet.destroyed_items(changes)
      assert changes.player.inv1 == final.object.guid
      assert ChangeSet.get_item(changes, replacement.object.guid, lookup([])) == nil
    end

    test "replaces the exact slot in a full backpack", %{original: original, replacement: replacement} do
      filler = for n <- 2..16, do: Item.build(%ItemTemplate{entry: 100 + n}, n, owner: 1)

      player =
        Enum.reduce(filler, %Player{inv1: original.object.guid}, &Map.put(&2, :"inv#{&1.object.guid}", &1.object.guid))

      batch = player |> Batch.new() |> Batch.replace(original.object.guid, replacement)
      assert {:ok, changes} = Inventory.plan(batch, lookup([original | filler]))
      assert changes.player.inv1 == replacement.object.guid
      assert [^original] = ChangeSet.destroyed_items(changes)
      assert [^replacement] = ChangeSet.placed_items(changes)
      assert ChangeSet.placement(changes, replacement.object.guid).position == {255, 23}
      assert changes.player.inv16 == 16
    end

    test "retains containment in carried and bank bags and permits unique self replacement", %{original: original} do
      original = %{original | internal: %{original.internal | template: %ItemTemplate{entry: 1, max_count: 1}}}
      replacement = Item.build(Item.template(original), 99, owner: 1)

      for {field, slot} <- [bag1: 19, bank_bag1: 63] do
        bag = Item.build(%ItemTemplate{entry: 50, inventory_type: 18, container_slots: 1}, 50, owner: 1)
        bag = %{bag | container: %{bag.container | slot_1: original.object.guid}}
        player = Map.put(%Player{bank_bag_slots: 1}, field, bag.object.guid)
        batch = player |> Batch.new() |> Batch.replace(original.object.guid, replacement)
        assert {:ok, changes} = Inventory.plan(batch, lookup([original, bag]))
        assert ChangeSet.placement(changes, 99).position == {slot, 0}
        assert [%{container: %{slot_1: 99}}] = ChangeSet.changed_items(changes)
        assert [%{item: %{contained: 50}}] = ChangeSet.placed_items(changes)
      end
    end

    test "enforces bag families and protects nonempty containers", %{original: original, replacement: replacement} do
      bag =
        Item.build(
          %ItemTemplate{entry: 50, class: 1, subclass: 2, bag_family: 4, inventory_type: 18, container_slots: 1},
          50,
          owner: 1
        )

      bag = %{bag | container: %{bag.container | slot_1: original.object.guid}}
      player = %Player{bag1: 50}
      batch = player |> Batch.new() |> Batch.replace(original.object.guid, replacement)
      assert {:error, :item_doesnt_go_to_slot} = Inventory.plan(batch, lookup([bag, original]))
      batch = player |> Batch.new() |> Batch.replace(50, replacement)
      assert {:error, :can_only_do_with_empty_bags} = Inventory.plan(batch, lookup([bag, original]))
    end

    test "rejects absent, foreign, existing, and repeated instances", %{original: original, replacement: replacement} do
      batch = %Player{inv1: original.object.guid} |> Batch.new() |> Batch.replace(original.object.guid, replacement)
      assert {:error, :item_not_found} = Inventory.plan(batch, lookup([]))
      assert {:error, :item_not_found} = Inventory.plan(batch, lookup([original, replacement]))
      foreign = %{original | item: %{original.item | owner: 2}}
      assert {:error, :item_not_found} = Inventory.plan(batch, lookup([foreign]))

      assert {:error, :item_not_found} =
               Inventory.plan(Batch.replace(batch, original.object.guid, replacement), lookup([original]))
    end

    test "counts banked unique replacements and keeps failed reagent removal uncommitted", %{original: original} do
      replacement = Item.build(%ItemTemplate{entry: 2, max_count: 1}, 99, owner: 1)
      duplicate = Item.build(Item.template(replacement), 98, owner: 1)
      reagent = Item.build(%ItemTemplate{entry: 3}, 97, owner: 1)
      player = %Player{inv1: original.object.guid, inv2: 97, bank1: 98}
      batch = player |> Batch.new() |> Batch.remove(3, 1) |> Batch.replace(original.object.guid, replacement)
      assert {:error, :cant_carry_more_of_this} = Inventory.plan(batch, lookup([original, duplicate, reagent]))
      assert player.inv1 == original.object.guid
      assert player.inv2 == 97
    end

    test "validates equipment and relocates the offhand atomically", %{original: original} do
      replacement = Item.build(%ItemTemplate{entry: 2, inventory_type: 17, bonding: 2}, 99, owner: 1)
      offhand = Item.build(%ItemTemplate{entry: 3, inventory_type: 14}, 98, owner: 1)
      player = %Player{mainhand: original.object.guid, offhand: 98}
      batch = player |> Batch.new() |> Batch.replace(original.object.guid, replacement)
      opts = [unit: %Unit{class: 1, race: 1, level: 60}, proficiency: Proficiency.all()]
      assert {:ok, changes} = Inventory.plan(batch, lookup([original, offhand]), opts)
      assert changes.player.mainhand == 99
      assert changes.player.offhand == 0
      assert changes.player.inv1 == 98
      assert changes.player.visible_item_16_0 == 2
      assert [%{item: %{flags: 1}}] = ChangeSet.placed_items(changes)
      assert {:error, :item_cant_be_equipped} = Inventory.plan(batch, lookup([original, offhand]))

      assert {:error, :cant_equip_reputation} =
               Inventory.plan(
                 batch,
                 lookup([original, offhand]),
                 Keyword.put(opts, :validate_item, fn _ -> {:error, :cant_equip_reputation} end)
               )

      full = Enum.reduce(1..16, player, &Map.put(&2, :"inv#{&1}", 100 + &1))
      batch = full |> Batch.new() |> Batch.replace(original.object.guid, replacement)
      assert {:error, :cant_equip_with_twohanded} = Inventory.plan(batch, lookup([original, offhand]), opts)
    end
  end

  defp items(_context) do
    %{
      original: Item.build(%ItemTemplate{entry: 1}, 1, owner: 1),
      replacement: Item.build(%ItemTemplate{entry: 2}, 99, owner: 1)
    }
  end

  defp lookup(items), do: &Enum.find(items, fn item -> item.object.guid == &1 end)
end
