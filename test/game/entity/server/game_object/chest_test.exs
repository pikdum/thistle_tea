defmodule ThistleTea.Game.Entity.Server.GameObject.ChestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.WorldRef

  defp chest_with_session do
    loot = %Loot{
      gold: 0,
      items: [%Loot.Item{slot: 0, item_id: 11_119, display_id: 1, count: 1, quality: 1, quest_item: true}]
    }

    %GameObject{
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        loot: %InternalLoot{id: 10_119, min_gold: 0, max_gold: 0, session: LootSession.new(loot, nil)}
      }
    }
  end

  describe "lootable?/1" do
    test "true only with loot config" do
      assert Chest.lootable?(chest_with_session())
      refute Chest.lootable?(%GameObject{internal: %Internal{world: %WorldRef{map_id: 0}}})
    end
  end

  describe "view/2" do
    test "returns the loot and tracks the viewer" do
      {result, state} = Chest.view(chest_with_session(), 42)

      assert {:ok, %Loot{items: [%Loot.Item{item_id: 11_119}]}} = result
      assert 42 in LootSession.viewers(state.internal.loot.session)
    end

    test "returns no loot once despawned" do
      state = chest_with_session()
      state = %{state | internal: %{state.internal | loot: %{state.internal.loot | corpse_removed?: true}}}

      assert {{:error, :no_loot}, _state} = Chest.view(state, 42)
    end

    test "returns no loot without loot config" do
      assert {{:error, :no_loot}, _state} =
               Chest.view(%GameObject{internal: %Internal{world: %WorldRef{map_id: 0}}}, 42)
    end
  end

  describe "take_item/2" do
    test "hands out the item once" do
      {result, state} = Chest.take_item(chest_with_session(), 0)

      assert {:ok, %Loot.Item{item_id: 11_119}} = result
      assert {{:error, _reason}, _state} = Chest.take_item(state, 0)
    end

    test "return_item restores a taken slot" do
      {_result, state} = Chest.take_item(chest_with_session(), 0)
      state = Chest.return_item(state, 0)

      assert {{:ok, %Loot.Item{item_id: 11_119}}, _state} = Chest.take_item(state, 0)
    end
  end

  describe "release/2" do
    test "keeps the chest while loot remains" do
      {_result, state} = Chest.view(chest_with_session(), 42)
      state = Chest.release(state, 42)

      refute state.internal.loot.corpse_removed?
      assert %LootSession{} = state.internal.loot.session
    end
  end
end
