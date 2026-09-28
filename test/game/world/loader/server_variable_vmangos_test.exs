defmodule ThistleTea.Game.World.Loader.ServerVariableVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Script

  @moduletag :vmangos_db

  describe "load_by_ids/2" do
    test "loads elemental invasion victory assignments" do
      scripts = Script.load_by_ids(Mangos.CreatureAiScript, [1_445_408, 1_445_708, 1_446_106, 1_446_407])

      for {id, variable} <- [{1_445_408, 30_011}, {1_445_708, 30_009}, {1_446_106, 30_008}, {1_446_407, 30_010}] do
        assert [%ScriptStep{command: :set_server_variable, datalong: ^variable, datalong2: 6}] = scripts[id]
      end
    end
  end

  describe "war-effort and fishing conditions" do
    test "evaluates imported global progress and winner conditions" do
      conditions = ConditionLoader.load_by_ids([1630, 1631, 264, 7716, 7715])
      initial = Context.new(world: %{saved_variables: %{}})
      advanced = Context.new(world: %{saved_variables: %{30_050 => 2, 30_056 => 1}})
      assert Evaluator.evaluate(initial, conditions[1630]) == :met
      assert Evaluator.evaluate(advanced, conditions[1630]) == :unmet
      assert Evaluator.evaluate(advanced, conditions[264]) == :met
      assert Evaluator.evaluate(initial, conditions[7716]) == :met
      assert Evaluator.evaluate(advanced, conditions[7715]) == :met
    end
  end
end
