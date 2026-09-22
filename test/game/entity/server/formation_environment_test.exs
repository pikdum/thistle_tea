defmodule ThistleTea.Game.Entity.Server.FormationEnvironmentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.FormationEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:formation]

  describe "snapshot/2" do
    test "reads published leader motion and excludes combat and other worlds", %{leader: leader, follower: follower} do
      leader = Movement.move_along_path(leader, [{10.0, 0.0, 0.0}], [velocity: 2.5], 0)
      World.update_position(leader)
      snapshot = FormationEnvironment.snapshot(follower, 1_000)
      assert snapshot.leader_ready?
      assert snapshot.leader_position == {leader.internal.world, 2.5, 0.0, 0.0}
      assert snapshot.path == [{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}]
      assert snapshot.arrives_at == 4_000

      Metadata.update(leader.object.guid, %{in_combat: true})
      refute FormationEnvironment.snapshot(follower, 1_000).leader_ready?
      Metadata.update(leader.object.guid, %{in_combat: false, unit_flags: 0x40000})
      refute FormationEnvironment.snapshot(follower, 1_000).leader_ready?

      World.update_position(%{leader | internal: %{leader.internal | world: WorldRef.instance(0, 0)}})
      snapshot = FormationEnvironment.snapshot(follower, 1_000)
      refute snapshot.leader_ready?
      assert snapshot.leader_position == nil
    end
  end

  describe "respawn_position/2" do
    @tag :namigator_maps
    test "uses the original leader's live position or spawn when dead", %{leader: leader, follower: follower} do
      position = {-5_508.87, -1_966.94, 399.491, 0.0}
      leader = %{leader | movement_block: %{leader.movement_block | position: position}}
      World.update_position(leader)
      {x, y, _z, angle} = FormationEnvironment.respawn_position(follower, 0)
      assert_in_delta x, -5_506.87, 0.01
      assert_in_delta y, -1_966.94, 0.01
      assert_in_delta abs(angle), :math.pi(), 0.001

      Metadata.update(leader.object.guid, %{alive?: false})
      {x, y, _z, _angle} = FormationEnvironment.respawn_position(follower, 0)
      assert_in_delta x, -5_508.57, 0.01
      assert_in_delta y, -2_000.05, 0.01
    end
  end

  defp formation(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    leader = mob(world)
    follower = mob(world)

    Enum.each([leader, follower], fn mob ->
      CreatureGroups.register(mob, self())
      Metadata.put(mob.object.guid, %{alive?: true, in_combat: false, orientation: 0.0, unit_flags: 0})
      World.update_position(mob)
    end)

    :ok = CreatureGroups.join(world, follower.object.guid, leader.object.guid, %Member{distance: 2.0, flags: 1}, self())

    on_exit(fn ->
      CreatureGroups.stop_world(world)

      Enum.each([leader, follower], fn mob ->
        World.remove_position(mob)
        Metadata.delete(mob.object.guid)
      end)
    end)

    %{leader: leader, follower: follower}
  end

  defp mob(world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 727, 8_000_000 + System.unique_integer([:positive]))},
      unit: %Unit{health: 100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, spawn: %Spawn{position: {-5_510.57, -2_000.05, 399.5}}}
    }
  end
end
