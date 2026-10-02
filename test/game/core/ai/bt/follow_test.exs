defmodule ThistleTea.Game.Core.AI.BT.FollowTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.BT.Follow
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.NavigationIntent
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @now 10_000

  describe "tick/3" do
    test "heads for its place behind a distant leader" do
      leader = leader(orientation: 0.0)
      follower = follower(leader, {20.0, 0.0, 0.0})

      assert {{:running, _delay, :follow}, moved, _blackboard} = tick(follower)
      assert [%NavigationIntent{destination: {x, y, +0.0}}] = moved.internal.navigation_intents
      assert_in_delta x, -3.0, 0.001
      assert_in_delta y, 0.0, 0.001
    end

    test "settles beside a leader who has stopped" do
      leader = leader(orientation: 0.0)
      follower = follower(leader, {-3.0, 0.0, 0.0})

      assert {{:running, _delay, :follow}, settled, _blackboard} = tick(follower)
      assert settled.internal.navigation_intents == []
    end

    test "waits in place while its leader is out of sight" do
      follower = follower(Guid.from_low_guid(:player, Unique.integer()), {20.0, 0.0, 0.0})

      assert {{:running, _delay, :follow}, waiting, _blackboard} = tick(follower)
      assert waiting.internal.navigation_intents == []
    end

    test "leaves other movement to the rest of the tree" do
      follower = %{follower(leader(orientation: 0.0), {20.0, 0.0, 0.0}) | internal: %Internal{world: world()}}

      assert {:failure, _state, _blackboard} = Follow.tick(follower, Blackboard.new(), Context.new(@now))
    end
  end

  describe "movement scripts" do
    test "follow the step's target at its distance and angle" do
      leader = leader(orientation: 0.0)
      mob = %{follower(leader, {20.0, 0.0, 0.0}) | internal: %Internal{world: world()}}

      step = %ScriptStep{command: :movement, datalong: 15, position: {4.0, 0.0, 0.0, -1.0}}
      context = Context.new(@now, random: Random.fixed(0.25))

      {_mob, blackboard} = Script.run(mob, Blackboard.new(), [step], leader, context)

      assert %{guid: ^leader, distance: 4.0, angle: angle} = Blackboard.following(blackboard)
      assert_in_delta angle, :math.pi() / 2, 0.001
    end

    test "another movement ends the follow" do
      leader = leader(orientation: 0.0)
      mob = follower(leader, {20.0, 0.0, 0.0})

      idle = %ScriptStep{command: :movement, datalong: 0}
      {_mob, blackboard} = Script.run(mob, mob.internal.blackboard, [idle], nil, Context.new(@now))

      assert Blackboard.following(blackboard) == nil
    end
  end

  describe "evading" do
    test "a follower drops combat where it stands instead of going home" do
      leader = leader(orientation: 0.0)
      follower = follower(leader, {20.0, 0.0, 0.0})
      follower = %{follower | internal: %{follower.internal | in_combat: true}}

      reset = MobBT.reset_after_combat(follower, AIEnvironment.context(follower, @now))

      refute reset.internal.in_combat
      refute reset.internal.blackboard.navigation.returning_home?
      assert %{guid: ^leader} = Blackboard.following(reset.internal.blackboard)
    end
  end

  defp tick(%Mob{} = follower) do
    Follow.tick(follower, follower.internal.blackboard, AIEnvironment.context(follower, @now))
  end

  defp leader(opts) do
    guid = Guid.from_low_guid(:player, Unique.integer())
    SpatialHash.update(:players, guid, world(), 0.0, 0.0, 0.0)
    Metadata.put(guid, %{orientation: Keyword.fetch!(opts, :orientation), alive?: true})

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp follower(leader, {x, y, z}) do
    blackboard = Blackboard.start_follow(Blackboard.new(), leader, 3.0, :math.pi())

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 2_208, Unique.integer()), entry: 2_208},
      unit: %Unit{health: 100, max_health: 100, level: 10, auras: [], bounding_radius: Unit.default_bounding_radius()},
      internal: %Internal{
        world: world(),
        blackboard: blackboard,
        spawn: %Spawn{position: {100.0, 100.0, 0.0}}
      },
      movement_block: %MovementBlock{position: {x, y, z, 0.0}, run_speed: 7.0}
    }
  end

  defp world, do: %WorldRef{map_id: 0}
end
