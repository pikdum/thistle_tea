defmodule ThistleTea.Game.Entity.Logic.ItemUseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemUse

  describe "plan/3" do
    test "retains a five-charge oil bottle until the fifth application" do
      item = Item.build(%ItemTemplate{entry: 20_744, spellid_1: 25_117, spellcharges_1: -5}, 101, owner: 1)

      item =
        Enum.reduce(1..4, item, fn used, item ->
          changes = use_item(item)
          assert changes.destroyed == %{}
          assert changes.player.inv1 == 101
          [updated] = ChangeSet.changed_items(changes)
          assert Item.spell_charge(updated, 1) == used - 5
          updated
        end)

      changes = use_item(item)
      assert [^item] = ChangeSet.destroyed_items(changes)
      assert changes.player.inv1 == 0
    end

    test "retains an exhausted positive-charge item and rejects another cast" do
      item = Item.build(%ItemTemplate{entry: 1, spellid_1: 10, spellcharges_1: 1}, 101, owner: 1)
      changes = use_item(item)
      assert changes.destroyed == %{}
      assert changes.player.inv1 == 101
      [empty] = ChangeSet.changed_items(changes)
      assert Item.spell_charge(empty, 1) == 0
      assert {:cast_error, 10, :no_charges_remain} = ItemUse.on_use_spell(empty)
      assert {:error, :no_charges_remain} = ItemUse.plan(Batch.new(changes.player), empty, 1)
    end

    test "consumes one stack unit and retains charges on the remaining units" do
      item =
        Item.build(%ItemTemplate{entry: 1, spellid_1: 10, spellcharges_1: -1, stackable: 20}, 101,
          owner: 1,
          stack_count: 5
        )

      changes = use_item(item)
      [remaining] = ChangeSet.changed_items(changes)
      assert remaining.item.stack_count == 4
      assert Item.spell_charge(remaining, 1) == -1
    end

    test "binds on use and preserves unrelated signed charge fields" do
      template = %ItemTemplate{
        entry: 1,
        bonding: 3,
        flags: 4,
        spellid_1: 10,
        spellcharges_1: 3,
        spellid_2: 11,
        spellcharges_2: -5
      }

      item = template |> Item.build(101, owner: 1) |> Item.unlock()
      assert item.item.flags == 4
      [used] = item |> use_item() |> ChangeSet.changed_items()
      assert used.item.flags == 5
      assert Item.spell_charge(used, 1) == 2
      assert Item.spell_charge(used, 2) == -4
      assert Item.spell_charge(used, 3) == 0
    end
  end

  defp use_item(item) do
    player = %Player{inv1: 101}
    {:ok, batch} = ItemUse.plan(Batch.new(player), item, 1)

    {:ok, changes} =
      Inventory.plan(batch, fn
        101 -> item
        _ -> nil
      end)

    changes
  end
end
