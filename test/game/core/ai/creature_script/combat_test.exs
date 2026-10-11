defmodule ThistleTea.Game.Core.AI.CreatureScript.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
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

  @entry 1_000

  describe "cast_on_creatures/4" do
    setup [:combatants]

    test "the original caster casts on each living creature", ctx do
      binding = Combat.cast_on_creatures(23_487, 12_099, 150, 0x22)
      boss_guid = ctx.boss.object.guid
      guard_guid = ctx.guard.object.guid
      {boss, _} = Script.execute_steps(ctx.boss, Blackboard.new(), [binding], nil, ctx.context)

      assert [%Effects.ScriptedEventCommand{source_guid: ^boss_guid, target_guid: ^boss_guid}] = boss.internal.events

      {guard, _} =
        Script.execute_steps(ctx.guard, Blackboard.new(), binding.sub_scripts[1], boss_guid, ctx.context)

      assert [%Effects.ForwardScriptSteps{target_guid: ^boss_guid, source_guid: ^guard_guid, steps: steps}] =
               guard.internal.events

      {boss, _} = Script.execute_steps(ctx.boss, Blackboard.new(), steps, guard_guid, ctx.context)

      assert [%Effects.TriggerSpell{source_guid: ^boss_guid, target_guid: ^guard_guid, spell_id: 23_487}] =
               boss.internal.events

      dead = %Observation{guid: guard_guid, metadata: %{alive?: false}}
      perception = %{ctx.context.perception | entities: %{guard_guid => dead}}

      {boss, _} =
        Script.execute_steps(ctx.boss, Blackboard.new(), steps, guard_guid, %{ctx.context | perception: perception})

      assert boss.internal.events == []
    end
  end

  describe "every/6" do
    test "rolls its first and repeat delays from ranges" do
      event = Combat.every(@entry, 1, Combat.cast(133), {2_000, 3_000}, 8_000)

      assert %{id: 100_001, event_type: :timer_in_combat, repeatable?: true} = event
      assert %{param1: 2_000, param2: 3_000, param3: 8_000, param4: 8_000} = event
    end

    test "tries a failed cast again instead of waiting out its repeat" do
      event = Combat.every(@entry, 1, [Combat.cast(133), Combat.talk(1)], 0, 8_000)

      assert event.check_result?

      assert [[%ScriptStep{command: :cast_spell, abort_on_failure?: true}, %ScriptStep{command: :talk} = talk]] =
               event.actions

      refute talk.abort_on_failure?
    end

    test "leaves conditional casts and opted-out timers alone" do
      conditional = %{Combat.cast(133) | condition: %Condition{type: :alive}}
      assert [[%ScriptStep{abort_on_failure?: false}]] = Combat.every(@entry, 1, conditional, 0, 8_000).actions

      unchecked = Combat.every(@entry, 2, Combat.cast(133), 0, 8_000, check_result?: false)
      refute unchecked.check_result?
    end
  end

  describe "below_health/6" do
    test "fires once or keeps repeating under its threshold" do
      once = Combat.below_health(@entry, 1, Combat.cast(133, :self), 30)
      assert %{event_type: :hp, param1: 30, repeatable?: false, check_result?: true} = once
      assert [[%ScriptStep{target_self?: true, abort_on_failure?: true}]] = once.actions

      repeating = Combat.below_health(@entry, 2, Combat.cast(133), 50, {10_000, 12_000}, condition: %Condition{})
      assert %{param1: 50, param3: 10_000, param4: 12_000, repeatable?: true, condition: %Condition{}} = repeating
    end
  end

  defp combatants(_context) do
    world = WorldRef.instance(409, Unique.integer())
    boss = creature(12_057, world)
    guard = creature(12_099, world)
    observation = %Observation{guid: guard.object.guid, metadata: %{alive?: true}}
    perception = Perception.new(0, nil, %{guard.object.guid => observation}, %{})
    %{boss: boss, guard: guard, context: Context.new(0, perception: perception)}
  end

  defp creature(entry, world) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, level: 63, auras: []},
      internal: %Internal{world: world, creature: %Creature{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
