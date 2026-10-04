defmodule ThistleTea.Game.Core.AI.CreatureScript.BelnistraszTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @belnistrasz 8_516

  describe "events/1" do
    test "he fights with Fireball and Frost Nova only while not chanting" do
      timers = Enum.filter(CreatureScript.events(@belnistrasz), &(&1.event_type == :timer_in_combat))

      assert timers |> Enum.map(&hd(hd(&1.actions)).datalong) |> Enum.sort() == [9_053, 11_831]
      assert Enum.all?(timers, &(&1.inverse_phase_mask == CreatureScript.only_in_phases([0]) and &1.not_casting?))
    end

    test "he cries out once when struck during the chant" do
      assert [%{actions: [[talk, warned]]} = aggro] =
               Enum.filter(CreatureScript.events(@belnistrasz), &(&1.event_type == :aggro))

      assert %ScriptStep{command: :talk, dataint: 9_008, dataint2: 9_007} = talk
      assert %ScriptStep{command: :set_phase, datalong: 2} = warned
      assert aggro.inverse_phase_mask == CreatureScript.only_in_phases([1])
    end

    test "he takes the chant's channel up again whenever a wave's death drops him out of the fight" do
      assert [%{actions: [[%ScriptStep{command: :cast_spell, datalong: 12_774, target_self?: true}]]} = evade] =
               Enum.filter(CreatureScript.events(@belnistrasz), &(&1.event_type == :evade))

      assert evade.inverse_phase_mask == CreatureScript.only_in_phases([1, 2])
    end
  end
end
