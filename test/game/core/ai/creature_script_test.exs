defmodule ThistleTea.Game.Core.AI.CreatureScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  describe "pick/1" do
    test "runs a lone choice as it is" do
      steps = [%ScriptStep{command: :despawn}]
      assert CreatureScript.pick([steps]) == steps
    end

    test "splits up to four choices evenly in one start_script" do
      choices = Enum.map(1..3, &[%ScriptStep{command: :set_phase, datalong: &1}])

      assert [%ScriptStep{command: :start_script} = step] = CreatureScript.pick(choices)
      assert ScriptStep.start_script_options(step) == [{1, 33}, {2, 33}, {3, 34}]
      assert Enum.map(1..3, &step.sub_scripts[&1]) == choices
    end

    test "nests more than four choices so each stays about as likely" do
      odds = 1..11 |> Enum.map(&[%ScriptStep{command: :set_phase, datalong: &1}]) |> CreatureScript.pick() |> odds(1.0)

      assert odds |> Map.keys() |> Enum.sort() == Enum.to_list(1..11)
      assert Enum.all?(Map.values(odds), &(abs(&1 - 1 / 11) < 0.005))
    end
  end

  defp odds([%ScriptStep{command: :set_phase, datalong: phase}], chance), do: %{phase => chance}

  defp odds([%ScriptStep{command: :start_script} = step], chance) do
    step
    |> ScriptStep.start_script_options()
    |> Enum.map(fn {id, share} -> odds(step.sub_scripts[id], chance * share / 100) end)
    |> Enum.reduce(&Map.merge/2)
  end
end
