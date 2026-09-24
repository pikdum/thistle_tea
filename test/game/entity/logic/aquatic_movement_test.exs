defmodule ThistleTea.Game.Entity.Logic.AquaticMovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.UnreachableTarget
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  setup [:fish]

  describe "try_aggro/3" do
    test "fish aggro swimmers while ignoring equally close dry targets", %{fish: fish} do
      idle = %{fish | unit: %{fish.unit | target: 0}, internal: %{fish.internal | in_combat: false, threat: %{}}}
      dry = context(fish, 1_000, false)
      assert {:failure, ignored, _} = MobBT.try_aggro(idle, Blackboard.new(), dry)
      refute ignored.internal.in_combat

      assert {:failure, engaged, _} = MobBT.try_aggro(idle, Blackboard.new(), context(fish, 1_000, true))
      assert engaged.unit.target == 7
      assert engaged.internal.in_combat
    end
  end

  describe "tick/3" do
    test "pursues underwater height and repaths when only target depth changes", %{fish: fish} do
      assert {{:running, _, :chase}, requested} = BehaviorRunner.tick(MobBT.tree(), fish, context(fish, 1_000, true))
      assert [%NavigationIntent{destination: {_, _, -15.0}}] = requested.internal.navigation_intents
      moving = NavigationResolver.resolve(requested, 1_000, fn _, _, destination, _ -> [destination] end)

      assert {{:running, _, :chase}, changed} =
               BehaviorRunner.tick(MobBT.tree(), moving, context(moving, 3_000, true, -1.0))

      assert [%NavigationIntent{destination: {_, _, -1.0}}] = changed.internal.navigation_intents
    end

    test "unreachable pursuit eventually uses the normal evade and home transition", %{fish: fish} do
      failed = failed_chase(fish, 1_000)
      failed = failed_chase(failed, 20_000)
      refute UnreachableTarget.expired?(failed, failed.internal.blackboard, 25_000)
      assert UnreachableTarget.expired?(failed, failed.internal.blackboard, 25_001)

      assert {_, returning} = BehaviorRunner.tick(MobBT.tree(), failed, context(failed, 25_001, false))
      refute returning.internal.in_combat
      assert returning.unit.target == 0
      assert returning.unit.health == returning.unit.max_health
      assert returning.internal.blackboard.navigation.unreachable_since == nil
    end
  end

  describe "record/4" do
    test "a partial route retains the timeout until the victim enters melee contact", %{fish: fish} do
      partial =
        fish
        |> NavigationIntent.enqueue({20.0, 0.0, -15.0}, chase_target: 7)
        |> NavigationResolver.resolve(1_000, fn _, _, _, _ -> [{5.0, 0.0, -20.0}] end)

      assert partial.internal.blackboard.navigation.unreachable_since == 1_000
      context = context(partial, 2_000, true)
      observation = %{context.perception.entities[7] | distance: 2.0}
      perception = %{context.perception | entities: Map.put(context.perception.entities, 7, observation)}
      contacted = UnreachableTarget.maintain(partial, %{context | perception: perception})
      assert contacted.internal.blackboard.navigation.unreachable_since == nil
    end

    test "successful routing and leaving combat clear a failed pursuit", %{fish: fish} do
      failed = failed_chase(fish, -30_000)
      assert UnreachableTarget.expired?(failed, failed.internal.blackboard, -5_999)

      succeeded =
        failed
        |> NavigationIntent.enqueue({20.0, 0.0, -15.0}, chase_target: 7)
        |> NavigationResolver.resolve(-5_000, fn _, _, destination, _ -> [destination] end)

      assert succeeded.internal.blackboard.navigation.unreachable_since == nil
      %{entity: left} = Engagement.leave(failed, :evade)
      assert left.internal.blackboard.navigation.unreachable_since == nil
    end

    test "a new victim starts a new timeout and control pauses do not retain stale failure", %{fish: fish} do
      failed = failed_chase(fish, 1_000)
      changed = %{failed | unit: %{failed.unit | target: 8}}
      changed = UnreachableTarget.record(changed, 8, false, 20_000)
      refute UnreachableTarget.expired?(changed, changed.internal.blackboard, 25_001)
      rooted = %{failed | internal: %{failed.internal | rooted?: true}}
      cleared = UnreachableTarget.maintain(rooted, context(rooted, 2_000, true))
      assert cleared.internal.blackboard.navigation.unreachable_since == nil
    end

    test "player companions, stationary casters and exempt creatures do not evade from failed paths", %{fish: fish} do
      owned = %{fish | unit: %{fish.unit | summoned_by: 1}}

      caster = %{
        fish
        | internal: %{fish.internal | blackboard: Blackboard.set_combat_movement(Blackboard.new(), false)}
      }

      exempt = %{fish | internal: %{fish.internal | creature: %{fish.internal.creature | extra_flags: 8}}}

      for entity <- [owned, caster, exempt] do
        failed = failed_chase(entity, 1_000)
        refute UnreachableTarget.expired?(failed, Blackboard.ensure(failed.internal.blackboard), 50_000)
      end
    end
  end

  defp failed_chase(fish, now) do
    fish
    |> NavigationIntent.enqueue({20.0, 0.0, -15.0}, chase_target: 7)
    |> NavigationResolver.resolve(now, fn _, _, _, _ -> nil end)
  end

  defp fish(_context) do
    fish = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1193, 1), entry: 1193, scale_x: 1.0},
      unit: %Unit{health: 50, max_health: 100, level: 5, flags: 0x8000, target: 7, combat_reach: 1.5},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, -20.0, 0.0},
        walk_speed: 2.5,
        run_speed: 7.0,
        movement_flags: 0
      },
      internal: %Internal{
        world: WorldRef.open(451),
        in_combat: true,
        threat: %{7 => 10.0},
        last_hostile_time: 1_000,
        blackboard: Blackboard.new(),
        creature: %Creature{inhabit_type: 2, static_flags: 0x10000000, spells: [], detection_range: 30.0},
        spawn: %Spawn{position: {0.0, 0.0, -20.0}, movement_type: 0}
      }
    }

    %{fish: fish}
  end

  defp context(fish, now, swimmable?, z \\ -15.0) do
    world = fish.internal.world
    guid = fish.object.guid

    source = %{
      alive?: true,
      level: 5,
      unit_flags: 0,
      faction_template: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
    }

    target = %{
      alive?: true,
      level: 5,
      unit_flags: 0,
      faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}
    }

    observations = %{
      guid => %Observation{guid: guid, position: {world, 0.0, 0.0, -20.0}, metadata: source},
      7 => %Observation{
        guid: 7,
        position: {world, 20.0, 0.0, z},
        grounded_position: {world, 20.0, 0.0, -30.0},
        distance: 20.0,
        metadata: target,
        swimmable?: swimmable?
      }
    }

    perception = Perception.new(now, {world, 0.0, 0.0, -20.0}, observations, %{players: [{7, 20.0}]})
    Context.new(now, perception: perception)
  end
end
