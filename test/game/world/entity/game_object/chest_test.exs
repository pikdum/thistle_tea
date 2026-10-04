defmodule ThistleTea.Game.World.Entity.GameObject.ChestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.InstanceDataSnapshot
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Loot
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Loot.Commit
  alias ThistleTea.Game.Core.Loot.LootSession
  alias ThistleTea.Game.Core.Loot.Release
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.GameObject.Chest
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Test.Unique

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

  describe "view/2 on a fresh chest" do
    setup [:conditioned_reference]

    test "expands a conditioned reference when the opener's copy meets it", context do
      {result, _state} = Chest.view(fresh_chest(context.loot_id), opener(context.guards_alive))

      assert {:ok, %Loot{items: [%Loot.Item{item_id: item_id}]}} = result
      assert item_id == context.item_id
    end

    test "leaves a conditioned reference out when the opener's copy misses it", context do
      {result, _state} = Chest.view(fresh_chest(context.loot_id), opener(context.guards_alive - 1))

      assert {:error, :nothing_to_take} = result
    end
  end

  defp conditioned_reference(_context) do
    ItemLoader.init()
    LootLoader.init()
    loot_id = Unique.integer()
    reference_id = Unique.integer()
    item_id = Unique.integer()
    guards_alive = 6

    condition = %Condition{entry: 1_600, type: :instance_data, value1: 15, value2: guards_alive, value3: 1}
    :ets.insert(ItemLoader, {item_id, %ItemTemplate{entry: item_id, name: "Tribute", quality: 2}})

    :ets.insert(
      LootLoader,
      {{:gameobject, loot_id},
       [%{item: 0, chance: 100.0, groupid: 0, mincount_or_ref: -reference_id, maxcount: 1, condition: condition}]}
    )

    :ets.insert(
      LootLoader,
      {{:reference, reference_id}, [%{item: item_id, chance: 100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}]}
    )

    on_exit(fn ->
      :ets.delete(LootLoader, {:gameobject, loot_id})
      :ets.delete(LootLoader, {:reference, reference_id})
      :ets.delete(ItemLoader, item_id)
    end)

    %{loot_id: loot_id, item_id: item_id, guards_alive: guards_alive}
  end

  defp fresh_chest(loot_id) do
    %GameObject{
      internal: %Internal{
        world: %WorldRef{map_id: 429, instance_id: 1},
        loot: %InternalLoot{id: loot_id, min_gold: 0, max_gold: 0}
      }
    }
  end

  defp opener(guards_alive) do
    snapshot = %InstanceDataSnapshot{
      world: %WorldRef{map_id: 429, instance_id: 1},
      status: :available,
      fields: %{15 => {:ok, guards_alive}}
    }

    %{@actor | condition_context: Context.new(world: %{instance_data: snapshot})}
  end
end
