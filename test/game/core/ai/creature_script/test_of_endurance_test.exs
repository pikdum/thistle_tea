defmodule ThistleTea.Game.Core.AI.CreatureScript.TestOfEnduranceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @grenka 4_490
  @harpy 4_100

  describe "event_steps/1" do
    test "the foodstuffs call a hidden Grenka unless one is already near" do
      [summon] = EventScript.steps_by_event()[747]

      assert %ScriptStep{
               command: :summon_creature,
               datalong: @grenka,
               dataint3: -1,
               dataint4: 1,
               concealed?: true,
               target_self?: true,
               condition: %Condition{type: :nearby_creature, value1: @grenka, value2: 100, reverse?: true}
             } = summon
    end

    test "Grenka's flock comes in three waves before she joins the fight" do
      steps = flock_script()

      assert [{5_000, 1}, {20_000, 2}, {35_000, 1}] =
               steps
               |> Enum.filter(&match?(%ScriptStep{command: :summon_creature, datalong: @harpy, dataint3: 0}, &1))
               |> Enum.frequencies_by(& &1.delay_ms)
               |> Enum.sort()

      assert [:set_concealed, :modify_flags, :attack_start] =
               steps |> Enum.reject(&(&1.command == :summon_creature)) |> Enum.map(& &1.command)

      assert steps |> Enum.reject(&(&1.command == :summon_creature)) |> Enum.all?(&(&1.delay_ms == 35_000))
    end
  end

  describe "events/1" do
    test "Grenka cannot fight while hidden and flees once when nearly dead" do
      [spawned, flee] = CreatureScript.events(@grenka)

      assert [[%ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x300, datalong3: 1}]] = spawned.actions
      assert %{event_type: :hp, param1: 15, repeatable?: false} = flee
    end
  end

  defp flock_script do
    [summon] = EventScript.steps_by_event()[747]
    [timed] = summon.sub_scripts[summon.dataint2]
    timed.sub_scripts[timed.datalong]
  end
end
