defmodule ThistleTea.Game.Entity.Logic.AI.BT.MobTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "wait_until_wander_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_250}

      assert {{:running, 250}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "succeeds when ready at explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_000}

      assert {:success, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_until_waypoint_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_waypoint_at: 1_250}

      assert {{:running, 250}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_for_arrival/3" do
    test "returns remaining movement duration from explicit time" do
      state = fixture_mob(start_time: 900, duration: 500)
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {{:running, 400}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "clears move target after arrival" do
      state = fixture_mob(start_time: 0, duration: 500)
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end
  end

  describe "move_to_target/3" do
    test "succeeds when already moving to target" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, ^blackboard} = MobBT.move_to_target(state, blackboard, 1_000)
    end

    test "fails and clears stale move target without a target" do
      state = fixture_mob()
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {:failure, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.move_to_target(state, blackboard, 1_000)
    end
  end

  describe "set_next_waypoint_wait/3" do
    test "schedules from explicit time and clears waypoint state" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, orientation: 1.5, wait_time: 250}

      assert {:success, ^state, %Blackboard{next_waypoint_at: 1_250, target: nil, orientation: nil, wait_time: nil}} =
               MobBT.set_next_waypoint_wait(state, blackboard, 1_000)
    end
  end

  describe "try_aggro/3" do
    test "aggros onto the nearest hostile player in range" do
      source_guid = mob_guid(17)
      target_guid = player_guid()
      other_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {10.0, 0.0, 0.0}, alliance(), 5)
      put_spatial_target(:players, other_guid, {12.0, 0.0, 0.0}, alliance(), 5)

      assert {:failure, state, %Blackboard{next_aggro_at: 2_000}} = MobBT.try_aggro(state, blackboard, 1_000)
      assert state.unit.target == target_guid
      assert state.internal.in_combat == true
      assert state.internal.last_hostile_time == 1_000
      assert [%Event{type: :attacker_gained, target_guid: ^target_guid}] = state.internal.events
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 0}
    end

    test "does not aggro neutral or friendly nearby units" do
      source_guid = mob_guid(17)
      friendly_guid = mob_guid(17)
      neutral_guid = mob_guid(32)

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:mobs, friendly_guid, {10.0, 0.0, 0.0}, defias(), 5)
      put_spatial_target(:mobs, neutral_guid, {8.0, 0.0, 0.0}, wolf(), 5)

      assert {:failure, ^state, %Blackboard{next_aggro_at: 2_000}} = MobBT.try_aggro(state, blackboard, 1_000)
    end

    test "uses level-adjusted aggro range" do
      source_guid = mob_guid(17)
      target_guid = player_guid()

      state = fixture_mob(guid: source_guid, level: 5, faction_template: 17)
      blackboard = %Blackboard{}

      put_metadata(source_guid, defias(), 5)
      put_spatial_target(:players, target_guid, {6.0, 0.0, 0.0}, alliance(), 30)

      assert {:failure, ^state, %Blackboard{next_aggro_at: 2_000}} = MobBT.try_aggro(state, blackboard, 1_000)
    end
  end

  defp fixture_mob(opts \\ []) do
    %Mob{
      object: %Object{
        guid: Keyword.get(opts, :guid, mob_guid(1))
      },
      unit: %Unit{
        level: Keyword.get(opts, :level, 1),
        faction_template: Keyword.get(opts, :faction_template, 17),
        flags: 0,
        target: 0
      },
      internal: %Internal{
        map: 0,
        in_combat: false,
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: {0.0, 0.0, 0.0}
      },
      movement_block: %MovementBlock{
        duration: Keyword.get(opts, :duration, 0),
        position: {0.0, 0.0, 0.0, 0.0},
        spline_nodes: [{1.0, 0.0, 0.0}]
      }
    }
  end

  defp put_spatial_target(table, guid, {x, y, z}, faction_template, level) do
    SpatialHash.update(table, guid, 0, x, y, z)
    put_metadata(guid, faction_template, level)

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)
  end

  defp put_metadata(guid, faction_template, level) do
    Metadata.put(guid, %{
      alive?: true,
      faction_template: faction_template,
      unit_flags: 0,
      level: level,
      attacker_count: 0
    })

    on_exit(fn -> Metadata.delete(guid) end)
  end

  defp player_guid do
    Guid.from_low_guid(:player, bounded_unique(0xFFFFFFFF))
  end

  defp mob_guid(entry) do
    Guid.from_low_guid(:mob, entry, bounded_unique(0x00FFFFFF))
  end

  defp bounded_unique(max) do
    rem(System.unique_integer([:positive]), max) + 1
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end
end
