defmodule ThistleTea.Game.Core.AI.CreatureScript.CapturedFelwoodOozeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @captured_ooze 10_290
  @primal_ooze 6_557

  describe "events/1" do
    test "melds with a primal ooze in reach, follows one nearby, and dissolves with none around" do
      [merge, follow, dissolve] = CreatureScript.events(@captured_ooze)

      assert Enum.all?([merge, follow, dissolve], &match?(%{event_type: :timer_ooc, param3: 2_000, param4: 2_000}, &1))

      assert [[%ScriptStep{command: :cast_spell, datalong: 16_032, target_param1: @primal_ooze, target_param2: 5}]] =
               merge.actions

      assert %Condition{type: :nearby_creature, value1: @primal_ooze, value2: 5, swap_targets?: true} = merge.condition

      assert [[%ScriptStep{command: :movement, datalong: 15, target_param2: 30, position: {2.0, +0.0, +0.0, +0.0}}]] =
               follow.actions

      assert %Condition{type: :and, children: [%Condition{value2: 30}, %Condition{value2: 5, reverse?: true}]} =
               follow.condition

      assert [[%ScriptStep{command: :despawn}]] = dissolve.actions
      assert %Condition{value2: 30, reverse?: true} = dissolve.condition
    end
  end
end
