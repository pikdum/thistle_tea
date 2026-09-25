defmodule ThistleTea.Game.Entity.Logic.AI.ScriptFailureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.AI.Script.Run
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "Script.run/5" do
    test "failed casts stop immediate and delayed steps only with the abort flag", %{mob: mob, cast: cast} do
      for abort? <- [true, false] do
        steps = [%{cast | abort_on_failure?: abort?}, phase(2), %{phase(3) | delay_ms: 1_000}]
        {result, blackboard} = Script.run(mob, Blackboard.new(), steps, nil, Context.new(0))
        assert blackboard.event_ai.phase == if(abort?, do: 0, else: 2)
        assert Enum.any?(result.internal.events, &is_struct(&1, Effects.ScriptSteps)) == not abort?
        refute Enum.any?(result.internal.events, &is_struct(&1, Effects.SpellStart))
      end
    end

    test "missing selectors and failing conditions honor abort before executing", %{mob: mob} do
      failures = [
        %{phase(1) | target_type: :victim, target_self?: true},
        %{phase(1) | condition: %Condition{type: :source_entry, value1: 999}},
        %{phase(1) | swap_initial?: true},
        %{phase(1) | swap_final?: true}
      ]

      for step <- failures, abort? <- [true, false] do
        steps = [%{step | abort_on_failure?: abort?}, phase(2)]
        {_, blackboard} = Script.run(mob, Blackboard.new(), steps, nil, Context.new(0))
        assert blackboard.event_ai.phase == if(abort?, do: 0, else: 2)
      end
    end

    test "a delayed failure cancels its remaining schedule", %{mob: mob, cast: cast} do
      steps = [%{cast | delay_ms: 1_000}, %{phase(2) | delay_ms: 2_000}]
      {scheduled, _} = Script.run(mob, Blackboard.new(), steps, nil, Context.new(0))
      assert [%Effects.ScriptSteps{steps: due, duration_ms: 1_000}] = scheduled.internal.events
      {failed, blackboard} = Script.run(mob, Blackboard.new(), due, nil, Context.new(1_000))
      assert failed.internal.events == []
      assert blackboard.event_ai.phase == 0
    end

    test "nested script termination does not terminate its parent", %{mob: mob, cast: cast} do
      child = %ScriptStep{command: :start_script, datalong: 7, dataint: 100, sub_scripts: %{7 => [cast, phase(1)]}}
      {_, blackboard} = Script.run(mob, Blackboard.new(), [child, phase(2)], nil, Context.new(0))
      assert blackboard.event_ai.phase == 2
    end
  end

  describe "EventAI.tick/4" do
    test "failed repeats retry on the next tick and consume the cooldown after success", %{mob: mob, cast: cast} do
      event = event([[cast, phase(2)]], repeatable?: true)
      mob = with_event(mob, event)
      {failed, blackboard} = EventAI.tick(mob, Blackboard.new(), -10_000, Context.new(-10_000))
      assert failed.internal.events == []
      assert blackboard.event_ai.phase == 0
      assert blackboard.event_ai.timers[0] == -10_000
      refute MapSet.member?(blackboard.event_ai.disabled, 0)

      ready = %{failed | unit: %{failed.unit | power1: 100}}
      {early, blackboard} = EventAI.tick(ready, blackboard, -9_001, Context.new(-9_001))
      assert early.internal.events == []
      {casted, blackboard} = EventAI.tick(ready, blackboard, -9_000, Context.new(-9_000))
      assert Enum.any?(casted.internal.events, &is_struct(&1, Effects.SpellStart))
      assert Enum.any?(casted.internal.events, &is_struct(&1, Effects.SpellGo))
      assert blackboard.event_ai.phase == 2
      assert blackboard.event_ai.timers[0] == 51_000

      {waiting, _} = EventAI.tick(clear_effects(casted), blackboard, -8_000, Context.new(-8_000))
      assert waiting.internal.events == []
    end

    test "one-shot events stay enabled after failure and disable after success", %{mob: mob, cast: cast} do
      mob = with_event(mob, event([[cast]]))
      {failed, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      refute MapSet.member?(blackboard.event_ai.disabled, 0)
      ready = %{failed | unit: %{failed.unit | power1: 100}}
      {casted, blackboard} = EventAI.tick(ready, blackboard, 1_000, Context.new(1_000))
      assert Enum.any?(casted.internal.events, &is_struct(&1, Effects.SpellGo))
      assert MapSet.member?(blackboard.event_ai.disabled, 0)
      {disabled, _} = EventAI.tick(clear_effects(casted), blackboard, 100_000, Context.new(100_000))
      assert disabled.internal.events == []
    end

    test "both script abort and event result checking are required for retries", %{mob: mob, cast: cast} do
      for {abort?, check?} <- [{false, true}, {true, false}] do
        event = %{event([[%{cast | abort_on_failure?: abort?}]]) | check_result?: check?}
        {failed, blackboard} = EventAI.tick(with_event(mob, event), Blackboard.new(), 0, Context.new(0))
        assert failed.internal.events == []
        assert MapSet.member?(blackboard.event_ai.disabled, 0)
        assert blackboard.event_ai.timers[0] == 60_000
      end
    end

    test "later action groups still execute and cannot erase an earlier failure", %{mob: mob, cast: cast} do
      mob = with_event(mob, event([[cast, phase(1)], [phase(2)]]))
      {_, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert blackboard.event_ai.phase == 2
      assert blackboard.event_ai.timers[0] == 0
      refute MapSet.member?(blackboard.event_ai.disabled, 0)
    end

    test "random events check only the selected action group", %{mob: mob, cast: cast} do
      mob = with_event(mob, %{event([[cast], [phase(2)]]) | random_action?: true})

      for selection <- [1, 2] do
        context = Context.new(0, random: Random.fixed(0.5, selection))
        {_, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, context)
        assert MapSet.member?(blackboard.event_ai.disabled, 0) == (selection == 2)
        assert blackboard.event_ai.phase == if(selection == 1, do: 0, else: 2)
      end
    end

    test "chance misses consume the event without requesting a retry", %{mob: mob, cast: cast} do
      mob = with_event(mob, %{event([[cast]]) | chance: 0})
      {_, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert MapSet.member?(blackboard.event_ai.disabled, 0)
      assert blackboard.event_ai.timers[0] == 60_000
    end

    test "direct EventAI actions ignore row delays", %{mob: mob} do
      mob = with_event(mob, event([[%{phase(2) | delay_ms: 5_000}]]))
      {result, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert result.internal.events == []
      assert blackboard.event_ai.phase == 2
    end
  end

  describe "EventAI.complete_script/4" do
    test "waits for every action group before retrying a failed event", %{mob: mob} do
      gate = %ScriptStep{command: :start_map_event, abort_on_failure?: true}
      mob = with_event(mob, event([[gate, phase(1)], [gate, phase(2)], [phase(3)]]))
      {waiting, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert blackboard.event_ai.phase == 3
      assert [first, second] = waiting.internal.events
      {waiting, blackboard} = resume(waiting, blackboard, first.reply, :failed, 10)
      assert [%Effects.ScriptCompleted{} = failed] = waiting.internal.events
      {waiting, blackboard} = EventAI.complete_script(waiting, blackboard, failed, 10)
      assert MapSet.member?(blackboard.event_ai.disabled, 0)
      assert blackboard.event_ai.timers[0] == 60_000
      {blocked, blackboard} = EventAI.tick(clear_effects(waiting), blackboard, 1_000, Context.new(1_000))
      assert blocked.internal.events == []
      {finished, blackboard} = resume(blocked, blackboard, second.reply, :continue, 1_010)
      assert blackboard.event_ai.phase == 2
      assert [%Effects.ScriptCompleted{} = success] = finished.internal.events
      {finished, blackboard} = EventAI.complete_script(finished, blackboard, success, 1_010)
      assert blackboard.event_ai.pending == %{}
      assert blackboard.event_ai.timers[0] == 1_010
      refute MapSet.member?(blackboard.event_ai.disabled, 0)
      assert EventAI.complete_script(finished, blackboard, failed, 2_000) == {finished, blackboard}
      assert EventAI.complete_script(finished, blackboard, success, 2_000) == {finished, blackboard}
    end

    test "successful or unchecked asynchronous actions keep their consumed cooldown", %{mob: mob} do
      for {result, check?} <- [{:continue, true}, {:failed, false}] do
        gate = %ScriptStep{command: :start_map_event, abort_on_failure?: true}
        mob = with_event(mob, %{event([[gate]]) | check_result?: check?})
        {waiting, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
        assert [effect] = waiting.internal.events
        {finished, blackboard} = resume(waiting, blackboard, effect.reply, result, 10)
        assert [%Effects.ScriptCompleted{} = completed] = finished.internal.events
        {_, blackboard} = EventAI.complete_script(finished, blackboard, completed, 10)
        assert MapSet.member?(blackboard.event_ai.disabled, 0)
        assert blackboard.event_ai.timers[0] == 60_000
        assert blackboard.event_ai.pending == %{}
      end
    end

    test "combat entry and evade invalidate pending tails", %{mob: mob} do
      gate = %ScriptStep{command: :start_map_event, abort_on_failure?: true}
      mob = with_event(mob, event([[gate, phase(9)]]))
      {waiting, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert [effect] = waiting.internal.events

      for reset <- [
            &EventAI.enter_combat(&1, &2, 7, 10, Context.new(10)),
            &EventAI.on_evade(&1, &2, 10, Context.new(10))
          ] do
        {reset, reset_blackboard} = reset.(waiting, blackboard)
        {finished, reset_blackboard} = resume(reset, reset_blackboard, effect.reply, :continue, 20)
        assert finished.internal.scripts.runs == %{}
        assert finished.internal.events == []
        assert reset_blackboard.event_ai.phase == 0
        assert reset_blackboard.event_ai.pending == %{}
      end
    end

    test "a local failure survives a later asynchronous success", %{mob: mob, cast: cast} do
      gate = %ScriptStep{command: :start_map_event}
      mob = with_event(mob, event([[cast], [gate]]))
      {waiting, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0))
      assert [effect] = waiting.internal.events
      {finished, blackboard} = resume(waiting, blackboard, effect.reply, :continue, 10)
      assert [%Effects.ScriptCompleted{} = completed] = finished.internal.events
      {_, blackboard} = EventAI.complete_script(finished, blackboard, completed, 10)
      refute MapSet.member?(blackboard.event_ai.disabled, 0)
      assert blackboard.event_ai.timers[0] == 10
    end
  end

  defp resume(state, blackboard, {id, receipt, world}, result, now),
    do: Run.resume(clear_effects(state), blackboard, id, receipt, world, result, Context.new(now))

  defp caster(_context) do
    spell = %Spell{id: 12_544, cast_time_ms: 0, power_type: 0, mana_cost: 20, effects: []}

    mob = %Mob{
      object: %Object{guid: 1, entry: 589},
      unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 100, power_type: 0, level: 14},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), creature: %Creature{}, spellbook: %{spell.id => spell}}
    }

    cast = %ScriptStep{command: :cast_spell, datalong: spell.id, target_self?: true, abort_on_failure?: true}
    %{mob: mob, cast: cast}
  end

  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}

  defp event(actions, opts \\ []) do
    %AIEvent{
      event_type: :timer_ooc,
      actions: actions,
      check_result?: true,
      repeatable?: Keyword.get(opts, :repeatable?, false),
      param3: 60_000,
      param4: 60_000
    }
  end

  defp with_event(mob, event),
    do: %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | ai_events: [event]}}}

  defp clear_effects(mob), do: %{mob | internal: %{mob.internal | events: []}}
end
