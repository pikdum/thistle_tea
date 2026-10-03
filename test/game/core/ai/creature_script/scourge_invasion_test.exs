defmodule ThistleTea.Game.Core.AI.CreatureScript.ScourgeInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mouth 16_995

  describe "events/1" do
    test "the Mouth of Kel'Thuzad taunts its zone now and then" do
      %{actions: [[taunt]]} = Enum.find(CreatureScript.events(@mouth), &(&1.event_type == :timer_ooc))

      assert %ScriptStep{command: :talk, datalong: 6} = taunt
      assert ScriptStep.talk_text_ids(taunt) == [13_126, 13_124, 13_122, 13_123]
    end

    test "the Mouth proclaims an attack and concedes a defeated zone before departing" do
      events = CreatureScript.events(@mouth)

      %{actions: [[start]]} = Enum.find(events, &(&1.event_type == :script_event and &1.param1 == 7))
      assert ScriptStep.talk_text_ids(start) == [13_121, 13_125]

      %{actions: [[concede, depart]]} = Enum.find(events, &(&1.event_type == :script_event and &1.param1 == 8))
      assert ScriptStep.talk_text_ids(concede) == [13_165, 13_164, 13_163]
      assert %ScriptStep{command: :despawn} = depart
    end
  end
end
