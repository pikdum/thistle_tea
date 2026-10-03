defmodule ThistleTea.Game.Core.AI.CreatureScript.WitchDoctorUnbagwaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @unbagwa 1_449
  @silverback 1_511
  @konda 1_516
  @mokk 1_514

  describe "quest_end_steps/0" do
    test "turning in the fangs sets three waves of apes on a passive Unbagwa" do
      [unflag, faction, first_event, first_apes] = CreatureScript.quest_end_steps()[349]

      assert %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 2} = unflag
      assert %ScriptStep{command: :set_faction, datalong: 113} = faction

      assert waves(first_event, first_apes) == [
               [{@silverback, 3}],
               [{@silverback, 4}, {@konda, 1}],
               [{@silverback, 5}, {@mokk, 1}]
             ]
    end

    test "each wave waits for its dead and a failure puts Unbagwa back to work" do
      [_unflag, _faction, first_event, _apes] = CreatureScript.quest_end_steps()[349]

      assert %ScriptStep{command: :start_map_event, datalong: 34_901, datalong2: 180} = first_event

      assert %Condition{type: :map_event_data, value1: 34_901, value2: 0, value3: 3, value4: 1} =
               first_event.success_condition

      assert [
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 1},
               %ScriptStep{command: :set_faction, datalong: 0}
             ] = first_event.sub_scripts[first_event.dataint4]

      assert Enum.all?(first_event.sub_scripts[first_event.dataint4], &match?(%Condition{type: :alive}, &1.condition))
    end
  end

  describe "events/1" do
    test "every fallen ape counts toward the wave in progress" do
      events = CreatureScript.events(@unbagwa)

      assert Enum.map(events, & &1.param1) == [@silverback, @konda, @mokk]

      for event <- events do
        assert [steps] = event.actions
        assert Enum.map(steps, & &1.datalong) == [34_901, 34_902, 34_903]
        assert Enum.all?(steps, &match?(%ScriptStep{command: :set_map_event_data, datalong3: 1, datalong4: 1}, &1))
      end
    end
  end

  defp waves(event, %ScriptStep{command: :start_script} = apes) do
    summons = Enum.map(apes.sub_scripts[apes.datalong], &{&1.datalong, &1.count})

    case event.sub_scripts[event.dataint2] do
      [%ScriptStep{command: :start_map_event} = next, next_apes] -> [summons | waves(next, next_apes)]
      _restore -> [summons]
    end
  end
end
