defmodule ThistleTea.Game.Entity.Logic.AI.ScriptRunTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.AI.Script.Run
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.WorldRef

  setup [:actor]

  describe "resume/7" do
    test "failure stops the tail only when requested", %{mob: mob} do
      for abort? <- [true, false] do
        steps = [gate(abort?), stand(1), %{stand(2) | delay_ms: 1_000}]
        {waiting, blackboard} = Script.run(mob, Blackboard.new(), steps, 7, -10_000)
        assert waiting.unit.stand_state == 0
        assert [%Effects.ScriptedEventCommand{reply: receipt}] = waiting.internal.events
        {result, _} = resume(waiting, blackboard, receipt, :failed, -9_900)
        assert result.unit.stand_state == if(abort?, do: 0, else: 1)
        assert map_size(result.internal.scripts.runs) == if(abort?, do: 0, else: 1)
        assert Enum.any?(result.internal.events, &is_struct(&1, Effects.ScriptSteps)) == not abort?
      end
    end

    test "keeps absolute due times and rejects replies from an earlier wait", %{mob: mob} do
      steps = [gate(), %{stand(1) | delay_ms: 1_000}, %{stand(2) | delay_ms: 2_000}]
      {waiting, blackboard} = Script.run(mob, Blackboard.new(), steps, 7, -10_000)
      assert [%Effects.ScriptedEventCommand{reply: first}] = waiting.internal.events
      {waiting, blackboard} = resume(waiting, blackboard, first, :continue, -9_600)
      assert [%Effects.ScriptSteps{duration_ms: 600, run_id: id, receipt: receipt}] = waiting.internal.events
      timer = {id, receipt, mob.internal.world}
      {duplicate, ^blackboard} = resume(waiting, blackboard, first, :continue, -9_000)
      assert duplicate.unit.stand_state == 0
      {waiting, blackboard} = resume(waiting, blackboard, timer, :continue, -9_000)
      assert waiting.unit.stand_state == 1
      assert [%Effects.ScriptSteps{duration_ms: 1_000, run_id: ^id, receipt: receipt}] = waiting.internal.events
      {finished, blackboard} = resume(waiting, blackboard, {id, receipt, mob.internal.world}, :continue, -7_500)
      assert finished.unit.stand_state == 2
      assert finished.internal.scripts.runs == %{}
      assert resume(finished, blackboard, timer, :continue, 0) == {finished, blackboard}
    end

    test "resumes from current entity and blackboard state", %{mob: mob} do
      increment = %ScriptStep{command: :set_phase, datalong: 1, datalong2: 1}
      {waiting, blackboard} = Script.run(mob, Blackboard.new(), [gate(), increment], 7, 0)
      assert [%Effects.ScriptedEventCommand{reply: receipt}] = waiting.internal.events
      waiting = %{waiting | unit: %{waiting.unit | health: 23}}
      blackboard = %{blackboard | event_ai: %{blackboard.event_ai | phase: 8}}
      {result, blackboard} = resume(waiting, blackboard, receipt, :continue, 50)
      assert result.unit.health == 23
      assert blackboard.event_ai.phase == 9
    end

    test "termination cancels matching invocations but preserves other scripts and targets", %{mob: mob} do
      blackboard = Blackboard.new()
      {waiting, blackboard} = Script.run(mob, blackboard, [gate(), stand(1)], 7, 0)
      {waiting, blackboard} = Script.run(waiting, blackboard, [gate(), stand(1)], 7, 0)
      {waiting, blackboard} = Script.run(waiting, blackboard, [%{stand(2) | script_id: 43, delay_ms: 1_000}], 7, 0)
      {waiting, blackboard} = Script.run(waiting, blackboard, [%{stand(3) | script_id: 42, delay_ms: 1_000}], 8, 0)
      [first, second, other_script, other_target] = waiting.internal.events
      {cancelled, blackboard} = resume(waiting, blackboard, first.reply, :terminated, 1)
      assert Map.keys(cancelled.internal.scripts.runs) |> Enum.sort() == [other_script.run_id, other_target.run_id]
      assert resume(cancelled, blackboard, second.reply, :continue, 2) == {cancelled, blackboard}
    end

    test "world changes discard the original tail", %{mob: mob} do
      {waiting, blackboard} = Script.run(mob, Blackboard.new(), [gate(), stand(1)], 7, 0)
      assert [%Effects.ScriptedEventCommand{reply: receipt}] = waiting.internal.events
      moved = %{waiting | internal: %{waiting.internal | world: WorldRef.open(1)}}
      {result, _} = resume(moved, blackboard, receipt, :continue, 1)
      assert result.unit.stand_state == 0
      assert result.internal.scripts.runs == %{}
    end
  end

  describe "clear/1" do
    test "old receipts cannot collide after returning to the same world", %{mob: mob} do
      {waiting, blackboard} = Script.run(mob, Blackboard.new(), [gate(), stand(1)], 7, 0)
      assert [%Effects.ScriptedEventCommand{reply: old}] = waiting.internal.events
      {waiting, blackboard} = Script.run(Run.clear(clear_effects(waiting)), blackboard, [gate(), stand(2)], 7, 10)
      assert [%Effects.ScriptedEventCommand{reply: current}] = waiting.internal.events
      refute old == current
      {unchanged, blackboard} = resume(waiting, blackboard, old, :continue, 11)
      assert unchanged.unit.stand_state == 0
      {finished, _} = resume(unchanged, blackboard, current, :continue, 12)
      assert finished.unit.stand_state == 2
    end
  end

  defp actor(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, stand_state: 0},
        internal: %Internal{world: WorldRef.open(0)}
      }
    }
  end

  defp gate(abort? \\ true),
    do: %ScriptStep{script_id: 42, command: :start_map_event, datalong: 7, datalong2: 60, abort_on_failure?: abort?}

  defp stand(value), do: %ScriptStep{script_id: 42, command: :stand_state, datalong: value}

  defp resume(state, blackboard, {id, receipt, world}, result, now),
    do: Run.resume(clear_effects(state), blackboard, id, receipt, world, result, Context.new(now))

  defp clear_effects(state), do: %{state | internal: %{state.internal | events: []}}
end
