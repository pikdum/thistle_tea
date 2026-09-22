defmodule ThistleTea.Game.Entity.Logic.AI.BT.FormationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Formation, as: Membership
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Formation, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.AI.BT.Formation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.WorldRef

  setup [:formation]

  describe "tick/3" do
    test "offsets the endpoint along the final segment and synchronizes actual path length", %{
      mob: mob,
      context: context
    } do
      {:failure, mob, blackboard} = Formation.sync(mob, Blackboard.new(), context)
      {_, mob, _} = Formation.tick(mob, blackboard, context)
      assert [%NavigationIntent{destination: destination, opts: opts}] = mob.internal.navigation_intents
      assert destination == {10.0, 2.0, 0.0}
      assert opts[:arrive_at] == 4_000
      path = fn _, _, _, _ -> [{0.0, 10.0, 0.0}, {10.0, 10.0, 0.0}, {10.0, 2.0, 0.0}] end
      resolved = NavigationResolver.resolve(mob, 0, path)
      assert resolved.movement_block.duration == 4_000
      assert Enum.any?(resolved.internal.events, &is_struct(&1, Effects.MonsterMove))
    end

    test "caps catch-up speed at 130 percent of run speed", %{mob: mob, context: context} do
      context = %{context | formation: %{context.formation | arrives_at: 100}}
      {:failure, mob, blackboard} = Formation.sync(mob, Blackboard.new(), context)
      {_, mob, _} = Formation.tick(mob, blackboard, context)
      resolved = NavigationResolver.resolve(mob, 0, fn _, _, destination, _ -> [destination] end)
      distance = :math.sqrt(104.0)
      assert_in_delta resolved.movement_block.duration, distance / 9.1 * 1_000, 1
    end

    test "does not start movement while the leader is stopped or fighting", %{mob: mob, context: context} do
      for changes <- [%{path: nil}, %{leader_ready?: false}, %{arrives_at: 0}] do
        snapshot = struct!(context.formation, changes)
        context = %{context | formation: snapshot}
        {:failure, mob, blackboard} = Formation.sync(mob, Blackboard.new(), context)
        {_, result, _} = Formation.tick(mob, blackboard, context)
        refute NavigationIntent.pending?(result)
      end
    end

    test "finishes its own leg before starting another", %{mob: mob, context: context} do
      {:failure, mob, blackboard} = Formation.sync(mob, Blackboard.new(), context)
      {_, mob, blackboard} = Formation.tick(mob, blackboard, context)
      mob = NavigationResolver.resolve(mob, 0, fn _, _, destination, _ -> [destination] end)
      {_, result, _} = Formation.tick(mob, blackboard, %{context | now: 100})
      refute NavigationIntent.pending?(result)
      assert result.internal.spline_id == mob.internal.spline_id
    end

    test "uses the existing teleport projection beyond visibility range", %{mob: mob, context: context} do
      mob = %{mob | movement_block: %{mob.movement_block | position: {-101.0, 0.0, 0.0, 0.0}}}
      {:failure, mob, blackboard} = Formation.sync(mob, Blackboard.new(), context)
      {_, result, _} = Formation.tick(mob, blackboard, context)
      assert result.movement_block.position == {0.0, 0.0, 0.0, 0.0}
      assert Enum.any?(result.internal.events, &is_struct(&1, Effects.CreatureTeleported))
    end

    test "suppresses the follower's original waypoint route", %{mob: mob, context: context} do
      mob = BT.init(mob, MobBT.tree())
      {_, result} = BT.tick(MobBT.tree(), mob, context)
      assert [%NavigationIntent{destination: destination}] = result.internal.navigation_intents
      assert destination == {10.0, 2.0, 0.0}
      assert result.internal.spawn.waypoint_route == mob.internal.spawn.waypoint_route
    end
  end

  describe "sync/3" do
    test "promotion continues the inherited cursor and disband restores personal patrol data", %{
      mob: mob,
      context: context
    } do
      route = %WaypointRoute{
        first_point: 4,
        destination_point: 4,
        points: %{
          4 => %Waypoint{position: {0.0, 0.0, 0.0, nil}, wait_time: 0},
          5 => %Waypoint{position: {20.0, 0.0, 0.0, nil}, wait_time: 0}
        }
      }

      membership = %{
        context.formation.membership
        | role: :leader,
          leader_guid: mob.object.guid,
          route: route,
          last_waypoint: 4
      }

      context = %{context | formation: %{context.formation | membership: membership}}
      mob = BT.init(mob, MobBT.tree())
      {_, result} = BT.tick(MobBT.tree(), mob, context)
      assert result.internal.blackboard.formation.route.destination_point == 4
      {_, result} = BT.tick(MobBT.tree(), result, %{context | now: 1_001})
      result = NavigationResolver.resolve(result, 1_001, fn _, _, _, _ -> [] end)
      {_, result} = BT.tick(MobBT.tree(), result, %{context | now: 1_002})
      assert result.internal.blackboard.formation.route.destination_point == 5
      assert result.internal.spawn.waypoint_route == mob.internal.spawn.waypoint_route
      {:failure, _, blackboard} = Formation.sync(result, result.internal.blackboard, %{context | formation: nil})
      assert blackboard.formation == nil
    end

    test "membership changes preserve combat movement", %{mob: mob, context: context} do
      mob = %{mob | internal: %{mob.internal | in_combat: true}}
      mob = Movement.move_along_path(mob, [{50.0, 0.0, 0.0}], [], 0)
      {:failure, result, _} = Formation.sync(mob, Blackboard.new(), %{context | now: 100})
      assert result.internal.movement_start_time == 0
      assert Movement.moving?(result, 100)
    end
  end

  describe "home_position/1" do
    test "leaders return to the last reached patrol waypoint", %{context: context} do
      membership = %{context.formation.membership | role: :leader, home_position: {30.0, 20.0, 1.0}}
      context = %{context | formation: %{context.formation | membership: membership}}
      assert Formation.home_position(context) == {30.0, 20.0, 1.0}
    end

    test "evade returns to the living formation's current location", %{mob: mob, context: context} do
      snapshot = %{context.formation | leader_position: {WorldRef.open(0), 50.0, 10.0, 2.0}}
      context = %{context | formation: snapshot}
      assert Formation.home_position(context) == {50.0, 12.0, 2.0}
      %{entity: mob} = Engagement.enter(mob, 99, 0, selection: :target)
      result = MobBT.reset_after_combat(mob, context)
      assert result.internal.blackboard.navigation.returning_home?
      assert result.internal.blackboard.navigation.move_target == {50.0, 12.0, 2.0}
    end
  end

  defp formation(_context) do
    member = %Member{distance: 2.0, angle: :math.pi() / 2, flags: 1}
    membership = %Membership{token: make_ref(), role: :follower, leader_guid: 200, member: member}

    snapshot = %Snapshot{
      membership: membership,
      leader_position: {WorldRef.open(0), 0.0, 0.0, 0.0},
      leader_orientation: 0.0,
      path: [{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}],
      started_at: 0,
      arrives_at: 4_000,
      leader_ready?: true
    }

    route = %WaypointRoute{
      first_point: 1,
      destination_point: 1,
      points: %{1 => %Waypoint{position: {-10.0, 0.0, 0.0, nil}}}
    }

    mob = %Mob{
      object: %Object{guid: 100},
      unit: %Unit{health: 100, max_health: 100, flags: 0, target: 0, level: 20},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        walk_speed: 2.5,
        run_speed: 7.0,
        movement_flags: 0
      },
      internal: %Internal{
        creature: %Creature{},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}, movement_type: 2, waypoint_route: route},
        in_combat: false
      }
    }

    %{mob: mob, context: Context.new(0, formation: snapshot)}
  end
end
