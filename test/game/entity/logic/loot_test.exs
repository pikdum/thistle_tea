defmodule ThistleTea.Game.Entity.Logic.LootTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Loot

  defp row(attrs) do
    Map.merge(%{item: 1, chance: 100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}, attrs)
  end

  defp no_references(_entry), do: []

  describe "roll/3" do
    test "drops items that pass their chance roll" do
      rows = [row(%{item: 10, chance: 50.0}), row(%{item: 20, chance: 30.0})]

      assert [{10, 1, false}] = Loot.roll(rows, &no_references/1, fn -> 0.4 end)
    end

    test "rolls quest items with negative chance and tags them" do
      rows = [row(%{item: 10, chance: -80.0})]

      assert [{10, 1, true}] = Loot.roll(rows, &no_references/1, fn -> 0.5 end)
      assert [] = Loot.roll(rows, &no_references/1, fn -> 0.9 end)
    end

    test "drops at most one item per group" do
      rows = [
        row(%{item: 10, chance: 60.0, groupid: 1}),
        row(%{item: 20, chance: 40.0, groupid: 1})
      ]

      assert [{10, 1, false}] = Loot.roll(rows, &no_references/1, fn -> 0.3 end)
      assert [{20, 1, false}] = Loot.roll(rows, &no_references/1, fn -> 0.7 end)
    end

    test "resolves references through the reference table" do
      rows = [row(%{item: 0, chance: 100.0, mincount_or_ref: -5000, maxcount: 1})]
      references = fn 5000 -> [row(%{item: 42, chance: 100.0})] end

      assert [{42, 1, false}] = Loot.roll(rows, references, fn -> 0.5 end)
    end

    test "rolls counts within min and max" do
      rows = [row(%{item: 10, chance: 100.0, mincount_or_ref: 2, maxcount: 4})]

      assert [{10, count, false}] = Loot.roll(rows, &no_references/1, fn -> 0.5 end)
      assert count in 2..4
    end
  end

  describe "take_item/2" do
    test "marks the slot as looted" do
      loot = %Loot{items: [%Loot.Item{slot: 0, item_id: 10}]}

      assert {:ok, %Loot.Item{item_id: 10}, loot} = Loot.take_item(loot, 0)
      assert {:error, :already_looted} = Loot.take_item(loot, 0)
    end

    test "rejects unknown slots" do
      assert {:error, :already_looted} = Loot.take_item(%Loot{}, 3)
    end
  end

  describe "take_gold/1" do
    test "takes the gold once" do
      assert {:ok, 25, loot} = Loot.take_gold(%Loot{gold: 25})
      assert {:error, :no_gold} = Loot.take_gold(loot)
    end
  end

  describe "empty?/1" do
    test "is empty when no gold and all items looted" do
      assert Loot.empty?(%Loot{})
      assert Loot.empty?(%Loot{gold: 0, items: [%Loot.Item{slot: 0, looted: true}]})
      refute Loot.empty?(%Loot{gold: 5})
      refute Loot.empty?(%Loot{items: [%Loot.Item{slot: 0}]})
    end
  end
end
