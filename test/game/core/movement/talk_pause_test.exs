defmodule ThistleTea.Game.Core.Movement.TalkPauseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement.TalkPause
  alias ThistleTea.Game.Core.WorldRef

  @now 5_000
  @until @now + 180_000

  describe "apply/2" do
    test "stops a wandering creature and holds its next step for three minutes" do
      mob = mob(:wander) |> walking_to({10.0, 0.0, 0.0})

      {mob, events} = TalkPause.apply(mob, @now)

      assert {5.0, +0.0, +0.0, _o} = mob.movement_block.position
      assert [%Effects.MovementStopped{}] = events
      assert %{target: nil, move_target: nil, next_wander_at: @until} = mob.internal.blackboard.navigation
    end

    test "keeps a patrolling creature's waypoint so it walks on afterwards" do
      mob = mob(:patrol) |> walking_to({10.0, 0.0, 0.0})

      {mob, _events} = TalkPause.apply(mob, @now)

      assert %{target: {10.0, +0.0, +0.0}, move_target: nil, next_waypoint_at: @until} =
               mob.internal.blackboard.navigation
    end

    test "never shortens a longer wait" do
      mob = mob(:patrol)
      blackboard = mob.internal.blackboard
      mob = put_blackboard(mob, %{blackboard | navigation: %{blackboard.navigation | next_waypoint_at: @until + 1}})

      {mob, []} = TalkPause.apply(mob, @now)

      assert mob.internal.blackboard.navigation.next_waypoint_at == @until + 1
    end

    test "leaves a cyclic patrol alone" do
      mob = mob(%Spawn{movement_type: 3, waypoint_route: %WaypointRoute{cyclic?: true}})

      assert {^mob, []} = TalkPause.apply(mob, @now)
    end

    test "leaves fighting, stationary, and keep-moving creatures alone" do
      fighting = %{mob(:wander) | internal: %{mob(:wander).internal | in_combat: true}}
      keep_moving = %{mob(:wander) | internal: %{mob(:wander).internal | creature: %Creature{extra_flags: 0x20}}}

      for mob <- [fighting, mob(:stand), keep_moving] do
        assert {^mob, []} = TalkPause.apply(mob, @now)
      end
    end

    test "leaves a scripted move alone" do
      mob = mob(:wander) |> walking_to({10.0, 0.0, 0.0})
      blackboard = mob.internal.blackboard
      mob = put_blackboard(mob, %{blackboard | navigation: %{blackboard.navigation | move_target: nil}})

      assert {^mob, []} = TalkPause.apply(mob, @now)
    end
  end

  defp walking_to(mob, target) do
    blackboard = mob.internal.blackboard
    navigation = %{blackboard.navigation | target: target, move_target: target}
    internal = %{mob.internal | movement_start_time: 0, movement_start_position: {0.0, 0.0, 0.0}}
    movement = %{mob.movement_block | duration: 10_000, spline_nodes: [target]}
    put_blackboard(%{mob | internal: internal, movement_block: movement}, %{blackboard | navigation: navigation})
  end

  defp put_blackboard(mob, blackboard), do: %{mob | internal: %{mob.internal | blackboard: blackboard}}

  defp mob(:wander), do: mob(%Spawn{movement_type: 1, distance: 5.0})
  defp mob(:patrol), do: mob(%Spawn{movement_type: 0, waypoint_route: %WaypointRoute{}})
  defp mob(:stand), do: mob(%Spawn{movement_type: 0})

  defp mob(%Spawn{} = spawn) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 10, flags: 0, target: 0, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: [], walk_speed: 2.5, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.open(0),
        blackboard: Blackboard.new(),
        creature: %Creature{extra_flags: 0},
        spawn: spawn
      }
    }
  end
end
