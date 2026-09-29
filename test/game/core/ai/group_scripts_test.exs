defmodule ThistleTea.Game.Core.AI.GroupScriptsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob

  describe "Script.run/5" do
    test "selects one nested script for the whole group and preserves its delays and target" do
      chosen = [%ScriptStep{command: :stand_state, datalong: 1, delay_ms: 2_000}]
      step = group_step(chosen)
      context = Context.new(100, random: Random.fixed(0.5, 51))

      for entity <- [%Mob{}, %Character{}] do
        entity = %{entity | object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}
        {entity, _} = Script.run(entity, Blackboard.new(), [step], 99, context)
        assert [%Effects.StartGroupScript{steps: ^chosen, target_guid: 99}] = entity.internal.events
      end

      assert ScriptStep.nested_script_ids(step) == [5, 6]
      assert ScriptStep.start_script_options(step) == [{5, 50}, {6, 25}]
    end

    test "a missed chance honors the abort flag" do
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{stand_state: 0}, internal: %Internal{}}
      context = Context.new(100, random: Random.fixed(0.5, 100))
      next = %ScriptStep{command: :stand_state, datalong: 1}

      for abort? <- [false, true] do
        step = %{group_step([]) | abort_on_failure?: abort?}
        {result, _} = Script.run(mob, Blackboard.new(), [step, next], 99, context)
        assert result.unit.stand_state == if(abort?, do: 0, else: 1)
        assert result.internal.events == []
      end
    end

    test "a non-unit source fails without dispatching a script" do
      source = %GameObject{object: %Object{guid: 1}, internal: %Internal{}}
      step = %{group_step([]) | abort_on_failure?: true}
      {result, _, status} = Script.execute_step(source, Blackboard.new(), step, 99, Context.new(0))
      assert status == :terminated
      assert result.internal.events == []
    end
  end

  defp group_step(chosen) do
    %ScriptStep{
      command: :start_script_on_group,
      datalong: 5,
      datalong2: 6,
      dataint: 50,
      dataint2: 25,
      sub_scripts: %{5 => [%ScriptStep{command: :stand_state, datalong: 3}], 6 => chosen}
    }
  end
end
