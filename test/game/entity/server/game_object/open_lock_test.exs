defmodule ThistleTea.Game.Entity.Server.GameObject.OpenLockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Gathering
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.Entity.Server.GameObject.OpenLock, as: ObjectLock
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @actor %Actor{guid: 42, group_id: nil, needed_items: MapSet.new(), distance: 0.0}
  @opened %OpenLock{lock_id: 38, lock_type: 3, skill_id: 186, value: 1, required: 0, gain?: true}

  setup [:vein]

  describe "open/5" do
    test "direct loot and concurrent opens cannot bypass access", %{state: state} do
      assert {{:error, :locked}, ^state} = Chest.view(state, @actor)
      assert {{:error, :locked}, ^state} = Chest.reserve_item(state, @actor, 0, self())
      assert {{:error, _}, ^state} = Chest.take_gold(state, @actor)
      assert Chest.release(state, @actor) == state
      assert {{:ok, %Loot{}, true}, opened} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)

      assert {{:error, :chest_in_use}, ^opened} =
               ObjectLock.open(opened, %{@actor | guid: 43}, @opened, true, attempt_roll: 0)

      assert {{:error, :locked}, ^opened} = Chest.view(opened, %{@actor | guid: 43})
    end

    test "failed attempts and stale targets do not claim a gain or create access", %{state: state} do
      assert {{:error, :try_again}, ^state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: -1)
      assert {{:error, :out_of_range}, ^state} = ObjectLock.open(state, %{@actor | distance: nil}, @opened, true)
      assert {{:error, :bad_targets}, ^state} = ObjectLock.open(state, @actor, %{@opened | lock_id: 39}, true)
      hidden = %{state | internal: %{state.internal | loot: %{state.internal.loot | corpse_removed?: true}}}
      assert {{:error, :bad_targets}, ^hidden} = ObjectLock.open(hidden, @actor, @opened, true)
    end

    test "reopening retains loot and allows at most one successful gain per player", %{state: state} do
      {{:ok, loot, false}, state} = ObjectLock.open(state, @actor, @opened, false, attempt_roll: 0)
      state = Chest.release(state, @actor)
      assert state.internal.gathering.uses == 0
      assert {{:error, :locked}, ^state} = Chest.view(state, @actor)
      {{:ok, ^loot, true}, state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
      state = Chest.release(state, @actor)
      {{:ok, ^loot, false}, state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
      state = Chest.release(state, @actor)
      assert {{:ok, ^loot, true}, state} = ObjectLock.open(state, %{@actor | guid: 43}, @opened, true, attempt_roll: 0)
      assert state.internal.gathering.skilled_players == MapSet.new([42, 43])
    end

    test "non-loot locks share the per-spawn gain limit", %{state: state} do
      state = %{state | internal: %{state.internal | loot: nil}}
      {{:ok, :activate, true}, state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
      assert {{:ok, :activate, false}, _state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
    end
  end

  describe "release/2 and respawn/1" do
    test "replenishes a vein, requires another cast, and clears gain history on respawn", %{state: state} do
      {{:ok, _loot, true}, state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
      state = drain(state) |> Chest.release(@actor)
      assert state.internal.gathering.uses == 1
      assert state.internal.gathering.opened_by == %{}
      assert state.internal.gathering.skilled_players == MapSet.new([42])
      assert state.internal.loot.session == nil
      refute state.internal.loot.corpse_removed?
      assert {{:error, :locked}, ^state} = Chest.view(state, @actor)

      state = %{
        state
        | internal: %{
            state.internal
            | loot: %{state.internal.loot | session: session()},
              gathering: %{state.internal.gathering | uses: 3}
          }
      }

      {{:ok, _loot, false}, state} = ObjectLock.open(state, @actor, @opened, true, attempt_roll: 0)
      state = drain(state) |> Chest.release(@actor)
      assert state.internal.gathering.uses == 4
      assert state.internal.loot.corpse_removed?
      assert World.position(state.object.guid) == nil
      respawned = Chest.respawn(state)
      refute respawned.internal.loot.corpse_removed?
      assert respawned.internal.gathering.uses == 0
      assert respawned.internal.gathering.skilled_players == MapSet.new()
      assert respawned.internal.gathering.opened_by == %{}
      assert World.position(state.object.guid) == {WorldRef.open(0), 0.0, 0.0, 0.0}
    end
  end

  defp drain(state) do
    {{:ok, reservation}, state} = Chest.reserve_item(state, @actor, 0, self())
    {:ok, state} = Chest.commit(state, %Commit{token: reservation.token, actor_guid: @actor.guid})
    state
  end

  defp session do
    LootSession.new(
      %Loot{gold: 0, items: [%Loot.Item{slot: 0, item_id: 2770, count: 1, display_id: 1, quality: 1}]},
      nil
    )
  end

  defp vein(_context) do
    guid = Guid.from_low_guid(:game_object, 1731, System.unique_integer([:positive, :monotonic]))

    state = %GameObject{
      object: %Object{guid: guid, entry: 1731},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        gathering: %Gathering{lock_id: 38, min_uses: 2, max_uses: 4},
        loot: %InternalLoot{id: 1, session: session()}
      }
    }

    on_exit(fn ->
      Metadata.delete(guid)
      SpatialHash.remove(:game_objects, guid)
    end)

    %{state: state}
  end
end
