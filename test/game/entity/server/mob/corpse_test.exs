defmodule ThistleTea.Game.Entity.Server.Mob.CorpseTest do
  use ExUnit.Case, async: false

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @dynamic_flag_lootable 0x0001
  @loot_id 999_201
  @quest_item_id 999_301
  @grey_item_id 999_302

  setup do
    ItemLoader.init()
    LootLoader.init()

    :ets.insert(ItemLoader, {@quest_item_id, %ItemTemplate{entry: @quest_item_id, name: "Wolf Ear", quality: 1}})
    :ets.insert(ItemLoader, {@grey_item_id, %ItemTemplate{entry: @grey_item_id, name: "Wolf Pelt", quality: 0}})

    killer = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

    on_exit(fn ->
      :ets.delete(LootLoader, {:creature, @loot_id})
      :ets.delete(ItemLoader, @quest_item_id)
      :ets.delete(ItemLoader, @grey_item_id)
      Metadata.delete(killer)
    end)

    {:ok, killer: killer}
  end

  describe "prepare/2" do
    test "leaves a quest-only corpse unlootable when the killer does not need the drop", %{killer: killer} do
      cache_loot_rows([quest_row()])
      Metadata.put(killer, %{needed_quest_items: MapSet.new()})

      prepared = Corpse.prepare(mob(killer), killer)

      assert (prepared.unit.dynamic_flags &&& @dynamic_flag_lootable) == 0
      assert {{:error, :no_loot}, _state} = Corpse.view(prepared, actor(killer))
    end

    test "keeps a quest-only corpse lootable for a killer on the quest", %{killer: killer} do
      cache_loot_rows([quest_row()])
      Metadata.put(killer, %{needed_quest_items: MapSet.new([@quest_item_id])})

      prepared = Corpse.prepare(mob(killer), killer)

      assert (prepared.unit.dynamic_flags &&& @dynamic_flag_lootable) != 0
      assert {{:ok, loot}, _state} = Corpse.view(prepared, actor(killer, [@quest_item_id]))
      assert [%{item_id: @quest_item_id}] = loot.items
    end

    test "finishes a mixed corpse once the wanted items are gone", %{killer: killer} do
      cache_loot_rows([quest_row(), grey_row()])
      Metadata.put(killer, %{needed_quest_items: MapSet.new()})

      prepared = Corpse.prepare(mob(killer), killer)

      assert {{:ok, loot}, prepared} = Corpse.view(prepared, actor(killer))
      assert [%{item_id: @grey_item_id, slot: 0}] = loot.items

      assert {{:ok, reservation}, reserved} = Corpse.reserve_item(prepared, actor(killer), 0, self())
      commit = %Commit{token: reservation.token, actor_guid: reservation.actor_guid}
      assert {:ok, looted} = Corpse.commit(reserved, commit)
      assert (looted.unit.dynamic_flags &&& @dynamic_flag_lootable) == 0
    end

    test "assumes a looter needs the drop when their needs are unknown", %{killer: killer} do
      cache_loot_rows([quest_row()])

      prepared = Corpse.prepare(mob(killer), killer)

      assert (prepared.unit.dynamic_flags &&& @dynamic_flag_lootable) != 0
    end

    test "restores a reservation when the player owner disappears", %{killer: killer} do
      cache_loot_rows([grey_row()])
      prepared = Corpse.prepare(mob(killer), killer)
      owner = spawn(fn -> receive do: (:stop -> :ok) end)

      assert {{:ok, reservation}, reserved} = Corpse.reserve_item(prepared, actor(killer), 0, owner)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, token, :process, ^owner, :killed}
      assert token == reservation.token
      restored = Corpse.reservation_lost(reserved, reservation.token)

      assert {{:ok, _reservation}, _state} = Corpse.reserve_item(restored, actor(killer), 0, self())
    end
  end

  describe "skin/4" do
    setup do
      :ets.insert(LootLoader, {{:skinning, @loot_id}, [grey_row()]})
      on_exit(fn -> :ets.delete(LootLoader, {:skinning, @loot_id}) end)
      :ok
    end

    test "waits for ordinary loot, claims once, and makes the skin private", %{killer: killer} do
      cache_loot_rows([grey_row()])
      prepared = Corpse.prepare(skinning_mob(killer), killer)
      assert {{:error, :target_not_looted}, ^prepared} = Corpse.skin(prepared, actor(killer), 300)
      assert {{:ok, reservation}, reserved} = Corpse.reserve_item(prepared, actor(killer), 0, self())
      assert {{:error, :target_not_looted}, ^reserved} = Corpse.skin(reserved, actor(killer), 300)
      assert {:ok, looted} = Corpse.commit(reserved, %Commit{token: reservation.token, actor_guid: killer})
      assert (looted.unit.flags &&& 0x04000000) != 0
      assert %{body_loot?: false} = Metadata.query(looted.object.guid, [:body_loot?])

      skinner = killer + 1
      assert {{:ok, loot, 1, 0}, skinned} = Corpse.skin(looted, actor(skinner), 300)
      assert [%{item_id: @grey_item_id}] = loot.items
      assert loot.gold == 0
      assert (skinned.unit.flags &&& 0x04000000) == 0
      assert {{:error, :target_unskinnable}, ^skinned} = Corpse.skin(skinned, actor(killer), 300)
      assert {{:error, :no_permission}, _} = Corpse.view(skinned, actor(killer))
      assert {{:error, :no_permission}, _} = Corpse.reserve_item(skinned, actor(killer), 0, self())

      closed = Corpse.release(skinned, actor(skinner))
      assert {{:ok, ^loot}, reopened} = Corpse.view(closed, actor(skinner))
      assert {{:ok, skin}, reserved} = Corpse.reserve_item(reopened, actor(skinner), 0, self())
      assert {:ok, finished} = Corpse.commit(reserved, %Commit{token: skin.token, actor_guid: skinner})
      assert (finished.unit.flags &&& 0x04000000) == 0
      assert (finished.unit.dynamic_flags &&& 1) == 0
      assert finished.internal.loot.skinned?
      assert {{:error, :target_unskinnable}, ^finished} = Corpse.skin(finished, actor(skinner), 300)
    end

    test "leaves a failed or out-of-range attempt available for retry", %{killer: killer} do
      cache_loot_rows([])
      prepared = Corpse.prepare(skinning_mob(killer), killer)
      assert {{:error, :out_of_range}, ^prepared} = Corpse.skin(prepared, %{actor(killer) | distance: 6.0}, 1)
      assert {{:error, :try_again}, ^prepared} = Corpse.skin(prepared, actor(killer), 1, roll: -1)
      assert {{:ok, _, _, _}, skinned} = Corpse.skin(prepared, actor(killer), 1, roll: 0)
      assert skinned.internal.loot.skinned?
    end

    test "empty skin tables cannot be rolled again", %{killer: killer} do
      cache_loot_rows([])
      :ets.insert(LootLoader, {{:skinning, @loot_id}, []})
      prepared = Corpse.prepare(skinning_mob(killer), killer)
      assert {{:ok, %{items: []}, _, _}, skinned} = Corpse.skin(prepared, actor(killer), 300)
      assert {{:error, :target_unskinnable}, ^skinned} = Corpse.skin(skinned, actor(killer), 300)
      assert skinned.internal.loot.session == nil
    end
  end

  describe "remove/2" do
    test "removes an unlootable corpse without a loot component", %{killer: killer} do
      corpse = mob(killer)
      corpse = %{corpse | internal: %{corpse.internal | loot: nil}}
      removed = Corpse.remove(corpse)
      assert Corpse.removed?(removed)
      assert Corpse.remove(removed) == removed
      assert removed.internal.loot.session == nil
    end

    test "ignores a decay timer from a previous creature life", %{killer: killer} do
      cache_loot_rows([])
      previous = Corpse.prepare(skinning_mob(killer), killer)
      respawned = Mob.respawn(previous)
      current = Corpse.prepare(%{respawned | unit: %{respawned.unit | health: 0}}, killer)

      refute current.internal.loot.corpse_token == previous.internal.loot.corpse_token
      assert Corpse.remove(current, previous.internal.loot.corpse_token) == current
    end
  end

  defp skinning_mob(killer) do
    mob = mob(killer)
    put_in(mob.internal.loot.skinning_id, @loot_id)
  end

  defp cache_loot_rows(rows), do: :ets.insert(LootLoader, {{:creature, @loot_id}, rows})

  defp actor(guid, needed_items \\ []) do
    %Actor{guid: guid, group_id: nil, needed_items: MapSet.new(needed_items), distance: 0.0}
  end

  defp quest_row, do: %{item: @quest_item_id, chance: -100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}
  defp grey_row, do: %{item: @grey_item_id, chance: 100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}

  defp mob(killer) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 299, System.unique_integer([:positive, :monotonic]))},
      unit: %Unit{health: 0, max_health: 10, level: 1, dynamic_flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        spawn: %Spawn{},
        loot: %InternalLoot{id: @loot_id, min_gold: 0, max_gold: 0, tapped_by: %{player: killer, group_id: nil}}
      }
    }
  end
end
