defmodule ThistleTea.Game.Core.AI.CreatureScript.CoreRagerLeashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:combatants]

  describe "events/1" do
    test "checks the boss every three seconds while fighting", ctx do
      {rager, blackboard} = EventAI.enter_combat(ctx.rager, Blackboard.new(), ctx.victim, 0, ctx.context)
      rager = clear_events(rager)

      {early, blackboard} = EventAI.tick(rager, blackboard, 2_000, %{ctx.context | now: 2_000})
      assert early.internal.events == []
      {ready, blackboard} = EventAI.tick(early, blackboard, 3_000, %{ctx.context | now: 3_000})
      assert [%Effects.ForwardScriptSteps{}] = ready.internal.events
      ready = clear_events(ready)

      {early, blackboard} = EventAI.tick(ready, blackboard, 5_000, %{ctx.context | now: 5_000})
      assert early.internal.events == []
      {ready, _} = EventAI.tick(early, blackboard, 6_000, %{ctx.context | now: 6_000})
      assert [%Effects.ForwardScriptSteps{}] = ready.internal.events
    end

    test "idle ragers do not leash the boss", ctx do
      idle = %{ctx.rager | internal: %{ctx.rager.internal | in_combat: false}, unit: %{ctx.rager.unit | target: 0}}
      {idle, _} = EventAI.tick(idle, Blackboard.new(), 10_000, %{ctx.context | now: 10_000})
      assert idle.internal.events == []
    end
  end

  describe "execute_steps/5" do
    test "uses a strict horizontal surface boundary", ctx do
      for x <- [104.0, 105.0] do
        context = boss_position(ctx, {ctx.world, x, 0.0, 1_000.0})
        {rager, _} = Script.execute_steps(ctx.rager, Blackboard.new(), ctx.steps, nil, context)
        assert rager.internal.events == []
      end

      {rager, _} = Script.execute_steps(ctx.rager, Blackboard.new(), ctx.steps, nil, ctx.context)
      assert [%Effects.ForwardScriptSteps{}] = rager.internal.events
    end

    test "forwards evade to the resolved boss owner", ctx do
      boss_guid = ctx.boss.object.guid
      rager_guid = ctx.rager.object.guid
      {rager, _} = Script.execute_steps(ctx.rager, Blackboard.new(), ctx.steps, nil, ctx.context)

      assert [%Effects.ForwardScriptSteps{target_guid: ^boss_guid, source_guid: ^rager_guid, steps: steps}] =
               rager.internal.events

      {boss, _} = Script.execute_steps(ctx.boss, Blackboard.new(), steps, rager_guid, ctx.context)
      assert [%Effects.EnterEvade{target_guid: ^boss_guid}] = boss.internal.events

      dead = %{ctx.boss | unit: %{ctx.boss.unit | health: 0}}
      {dead, _} = Script.execute_steps(dead, Blackboard.new(), steps, rager_guid, ctx.context)
      assert dead.internal.events == []
    end

    test "missing and other-copy bosses are ignored", ctx do
      missing = %{ctx.context | script_targets: %{}, perception: Perception.new(0, nil, %{}, %{})}
      {rager, _} = Script.execute_steps(ctx.rager, Blackboard.new(), ctx.steps, nil, missing)
      assert rager.internal.events == []

      other_world = WorldRef.instance(409, Unique.integer())
      context = boss_position(ctx, {other_world, 106.0, 0.0, 0.0})
      {rager, _} = Script.execute_steps(ctx.rager, Blackboard.new(), ctx.steps, nil, context)
      assert rager.internal.events == []
    end
  end

  defp combatants(_context) do
    world = WorldRef.instance(409, Unique.integer())
    victim = Guid.from_low_guid(:player, Unique.integer())
    event = Enum.find(CreatureScript.events(11_672), &(&1.event_type == :timer_in_combat and &1.param1 == 3_000))
    rager = creature(11_672, world, 1.0)
    rager = %{rager | unit: %{rager.unit | target: victim}, internal: %{rager.internal | in_combat: true}}
    rager = %{rager | internal: %{rager.internal | creature: %{rager.internal.creature | ai_events: [event]}}}
    boss = creature(11_988, world, 4.0)
    observation = %Observation{guid: boss.object.guid, metadata: %{bounding_radius: 4.0}}
    perception = Perception.new(0, nil, %{boss.object.guid => observation}, %{})

    context =
      Context.new(0,
        perception: perception,
        script_targets: %{{:creature_from_instance_data, 12, 0} => boss.object.guid}
      )

    ctx = %{
      rager: rager,
      boss: boss,
      world: world,
      victim: victim,
      context: context,
      steps: List.flatten(event.actions)
    }

    %{ctx | context: boss_position(ctx, {world, 106.0, 0.0, 0.0})}
  end

  defp boss_position(ctx, position) do
    perception = ctx.context.perception
    guid = ctx.boss.object.guid
    observation = %{perception.entities[guid] | position: position}
    %{ctx.context | perception: %{perception | entities: %{guid => observation}}}
  end

  defp clear_events(entity), do: %{entity | internal: %{entity.internal | events: []}}

  defp creature(entry, world, radius) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, level: 63, bounding_radius: radius, auras: []},
      internal: %Internal{world: world, creature: %Creature{db_guid: Unique.integer()}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
