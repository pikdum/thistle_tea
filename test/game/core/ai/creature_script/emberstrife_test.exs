defmodule ThistleTea.Game.Core.AI.CreatureScript.EmberstrifeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @emberstrife 10_321

  describe "events/1" do
    test "he cleaves and breathes fire at his victim" do
      casts =
        for %{event_type: :timer_in_combat, actions: [[%ScriptStep{datalong: spell, target_type: :victim}]]} <-
              CreatureScript.events(@emberstrife),
            do: spell

      assert casts == [19_983, 9_573]
    end

    test "below 60 percent he frenzies every two minutes" do
      assert [frenzy, _weakened] = Enum.filter(CreatureScript.events(@emberstrife), &(&1.event_type == :hp))

      assert %{param1: 60, param2: 0, param3: 120_500, param4: 120_500, repeatable?: true} = frenzy

      assert [[%ScriptStep{command: :cast_spell, datalong: 8_269, target_self?: true}, %ScriptStep{dataint: 7_797}]] =
               frenzy.actions
    end

    test "he is weakened once he falls below 11 percent" do
      assert [_frenzy, weakened] = Enum.filter(CreatureScript.events(@emberstrife), &(&1.event_type == :hp))

      assert %{param1: 11, param2: 0, repeatable?: false} = weakened
      assert [[%ScriptStep{command: :talk, dataint: 11_476}]] = weakened.actions
    end
  end
end
