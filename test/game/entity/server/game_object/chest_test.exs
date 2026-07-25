defmodule ThistleTea.Game.Entity.Server.GameObject.ChestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.WorldRef

  @actor %Actor{guid: 42, group_id: nil, needed_items: MapSet.new([11_119]), distance: 0.0}

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
      {result, state} = Chest.view(chest_with_session(), @actor)

      assert {:ok, %Loot{items: [%Loot.Item{item_id: 11_119}]}} = result
      assert 42 in LootSession.viewers(state.internal.loot.session)
    end

    test "returns no loot once despawned" do
      state = chest_with_session()
      state = %{state | internal: %{state.internal | loot: %{state.internal.loot | corpse_removed?: true}}}

      assert {{:error, :no_loot}, _state} = Chest.view(state, @actor)
    end

    test "returns no loot without loot config" do
      assert {{:error, :no_loot}, _state} =
               Chest.view(%GameObject{internal: %Internal{world: %WorldRef{map_id: 0}}}, @actor)
    end
  end

  describe "reserve_item/4" do
    test "hands out the item only after commit" do
      {result, state} = Chest.reserve_item(chest_with_session(), @actor, 0, self())

      assert {:ok, reservation} = result
      assert {{:error, _reason}, _state} = Chest.reserve_item(state, @actor, 0, self())

      commit = %Commit{token: reservation.token, actor_guid: reservation.actor_guid}
      assert {:ok, state} = Chest.commit(state, commit)
      assert {{:error, _reason}, _state} = Chest.reserve_item(state, @actor, 0, self())
    end

    test "release restores a reserved slot" do
      {{:ok, reservation}, state} = Chest.reserve_item(chest_with_session(), @actor, 0, self())
      release = %Release{token: reservation.token, actor_guid: reservation.actor_guid}
      assert {:ok, state} = Chest.release_reservation(state, release)

      assert {{:ok, _reservation}, _state} = Chest.reserve_item(state, @actor, 0, self())
    end
  end

  describe "release/2" do
    test "keeps the chest while loot remains" do
      {_result, state} = Chest.view(chest_with_session(), @actor)
      state = Chest.release(state, @actor)

      refute state.internal.loot.corpse_removed?
      assert %LootSession{} = state.internal.loot.session
    end
  end
end
