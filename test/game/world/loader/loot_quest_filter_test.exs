defmodule ThistleTea.Game.World.Loader.LootQuestFilterTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  @loot_id 999_001
  @quest_item_id 999_101
  @grey_item_id 999_102

  setup do
    ItemLoader.init()
    LootLoader.init()

    :ets.insert(ItemLoader, {@quest_item_id, %ItemTemplate{entry: @quest_item_id, name: "Wolf Ear", quality: 1}})
    :ets.insert(ItemLoader, {@grey_item_id, %ItemTemplate{entry: @grey_item_id, name: "Wolf Pelt", quality: 0}})

    :ets.insert(
      LootLoader,
      {{:creature, @loot_id},
       [
         %{item: @quest_item_id, chance: -100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1},
         %{item: @grey_item_id, chance: 100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}
       ]}
    )

    on_exit(fn ->
      :ets.delete(LootLoader, {:creature, @loot_id})
      :ets.delete(ItemLoader, @quest_item_id)
      :ets.delete(ItemLoader, @grey_item_id)
    end)

    :ok
  end

  describe "generate/4" do
    test "keeps a quest drop a looter still needs" do
      loot = LootLoader.generate(@loot_id, 0, 0, &(&1 == @quest_item_id))

      assert [%Loot.Item{item_id: @quest_item_id, quest_item: true, slot: 0}, %Loot.Item{item_id: @grey_item_id}] =
               loot.items
    end

    test "drops a quest item nobody needs and keeps slots contiguous" do
      loot = LootLoader.generate(@loot_id, 0, 0, fn _item_id -> false end)

      assert [%Loot.Item{item_id: @grey_item_id, quest_item: false, slot: 0}] = loot.items
    end

    test "an unwanted quest-only roll leaves the loot empty" do
      :ets.insert(
        LootLoader,
        {{:creature, @loot_id}, [%{item: @quest_item_id, chance: -100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}]}
      )

      loot = LootLoader.generate(@loot_id, 0, 0, fn _item_id -> false end)

      assert Loot.empty?(loot)
    end

    test "keeps quest drops when no filter is given" do
      loot = LootLoader.generate(@loot_id, 0, 0)

      assert Enum.any?(loot.items, &(&1.item_id == @quest_item_id))
    end
  end
end
