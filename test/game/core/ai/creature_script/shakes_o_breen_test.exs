defmodule ThistleTea.Game.Core.AI.CreatureScript.ShakesOBreenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @shakes 2_610
  @death_from_below 667

  describe "quest_start_steps/0" do
    test "accepting the quest sounds the alarm and fails if Shakes dies or the player strays" do
      assert [
               %ScriptStep{command: :talk, dataint: 6_372},
               %ScriptStep{command: :start_map_event, datalong: @death_from_below} = event,
               %ScriptStep{command: :set_phase, datalong: 1},
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 2},
               %ScriptStep{command: :start_script, sub_scripts: %{1 => _waves}}
             ] = steps()

      assert event.failure_condition == %Condition{type: :escort, value1: 1, value2: 150}

      assert [%ScriptStep{command: :fail_quest}, %ScriptStep{command: :respawn_creature, datalong: 1}] =
               event.sub_scripts[event.dataint4]
    end

    test "three naga waves come ashore twenty seconds apart while the defense lasts" do
      %ScriptStep{sub_scripts: %{1 => waves}} = List.last(steps())

      assert Enum.all?(waves, &(&1.condition == %Condition{type: :map_event_active, value1: @death_from_below}))

      assert waves |> Enum.filter(&(&1.command == :summon_creature)) |> Enum.map(&{&1.delay_ms, &1.datalong}) == [
               {20_000, 2_595},
               {20_000, 2_595},
               {20_000, 2_596},
               {40_000, 2_595},
               {40_000, 2_595},
               {60_000, 2_595},
               {60_000, 2_595},
               {60_000, 2_596}
             ]

      assert [%ScriptStep{command: :talk, dataint: 854}] =
               waves |> Enum.find(&(&1.command == :summon_creature)) |> then(& &1.sub_scripts[&1.dataint2])

      assert %ScriptStep{delay_ms: 60_000} =
               Enum.find(waves, &match?(%ScriptStep{command: :set_phase, datalong: 2}, &1))
    end
  end

  describe "events/1" do
    test "the quest completes once no naga of the last wave is left" do
      events = CreatureScript.events(@shakes)

      assert Enum.map(events, &{&1.event_type, &1.param1}) == [
               {:summoned_just_died, 2_595},
               {:summoned_just_died, 2_596},
               {:summoned_just_despawn, 2_595},
               {:summoned_just_despawn, 2_596}
             ]

      assert Enum.all?(events, &(&1.inverse_phase_mask == CreatureScript.only_in_phases([2])))
      [died | _] = events

      assert %Condition{type: :and, children: [raiders, sorceresses]} = died.condition
      assert %Condition{type: :nearby_creature, value1: 2_595, reverse?: true, swap_targets?: true} = raiders
      assert %Condition{type: :nearby_creature, value1: 2_596, reverse?: true, swap_targets?: true} = sorceresses

      assert [
               %ScriptStep{command: :quest_explored, datalong: @death_from_below, datalong3: 1},
               %ScriptStep{command: :end_map_event, datalong2: 1},
               %ScriptStep{command: :set_phase, datalong: 0},
               %ScriptStep{command: :modify_flags, datalong3: 1}
             ] = List.flatten(died.actions)
    end
  end

  defp steps, do: Map.fetch!(CreatureScript.quest_start_steps(), @death_from_below)
end
