defmodule ThistleTea.Game.Core.AI.CreatureScript.KindalMoonweaverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.KindalMoonweaver
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @kindal 7_956
  @sprite 7_997
  @quest 2_969
  @sprite_event 7_997

  describe "events/1" do
    test "Kindal shouts one of four battle cries when attacked" do
      assert [%{event_type: :aggro, actions: [[talk]]}] = CreatureScript.events(@kindal)
      assert %ScriptStep{command: :talk, dataint: 4_122, dataint2: 4_123, dataint3: 4_124, dataint4: 4_125} = talk
    end

    test "a sprite darter that dies counts as lost and its corpse goes ten seconds later" do
      assert [%{event_type: :death, actions: [[lost, despawn]]}] = CreatureScript.events(@sprite)
      assert %ScriptStep{command: :set_map_event_data, datalong: @sprite_event, datalong2: 1, datalong4: 1} = lost

      assert %ScriptStep{
               command: :start_script,
               sub_scripts: %{1 => [%ScriptStep{command: :despawn, delay_ms: 10_000}]}
             } =
               despawn
    end
  end

  describe "routes/0" do
    test "eleven escape routes run from the pen's exits out of the camp, saving the sprite at the end" do
      routes = CreatureScript.routes() |> Enum.filter(&(&1.entry == @sprite))

      assert Enum.map(routes, & &1.variant) == Enum.to_list(1..11)
      assert %Route{path: [{-4529.44, 825.49, 60.51, 0}, {-4563.52, 877.13, 61.07, 0}]} = hd(routes)
      assert %Route{path: [{-4513.14, 765.45, 60.72, 0}, {-4515.88, 696.60, 64.38, 0}]} = List.last(routes)

      for %Route{points: points} <- routes do
        assert %{1 => [saved, %ScriptStep{command: :despawn}]} = points
        assert %ScriptStep{command: :set_map_event_data, datalong: @sprite_event, datalong2: 0} = saved
      end
    end
  end

  describe "escape_steps/0" do
    test "a freed sprite turns friendly and runs one of the escape routes a moment after the others" do
      assert [%ScriptStep{command: :set_faction, datalong: 10}, %ScriptStep{command: :set_run, datalong: 1} | pick] =
               KindalMoonweaver.escape_steps()

      starts = leaves(pick)
      assert Enum.map(starts, & &1.dataint3) |> Enum.sort() == Enum.to_list(1..11)
      assert Enum.all?(starts, &match?(%ScriptStep{command: :start_waypoints, datalong: 5}, &1))
      assert starts |> Enum.map(& &1.delay_ms) |> Enum.min_max() == {0, 2_727}
    end
  end

  describe "quest_start_steps/0" do
    test "Kindal stands, speaks, and follows the player three seconds later" do
      %{@quest => [quest_event, sprite_event | steps]} = CreatureScript.quest_start_steps()

      assert [
               %ScriptStep{command: :stand_state, datalong: 0},
               %ScriptStep{command: :turn_to},
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x200, datalong3: 2},
               %ScriptStep{command: :talk, dataint: 4_079},
               %ScriptStep{command: :set_faction, datalong: 231},
               %ScriptStep{command: :modify_flags, datalong: 147, datalong3: 2},
               %ScriptStep{command: :movement, datalong: 15, delay_ms: 3_000}
             ] = steps

      assert %ScriptStep{command: :start_map_event, datalong: @quest, datalong2: 360} = quest_event
      assert quest_event.failure_condition == %Condition{type: :escort, value1: 1, value2: 100}
      assert quest_event.success_condition == nil
      assert %ScriptStep{command: :start_map_event, datalong: @sprite_event} = sprite_event
    end

    test "six sprites saved complete the quest, and its own failure silences the sprite count" do
      %{@quest => [quest_event, sprite_event | _steps]} = CreatureScript.quest_start_steps()

      assert sprite_event.success_condition ==
               %Condition{type: :map_event_data, value1: @sprite_event, value2: 0, value3: 6, value4: 1}

      assert [%ScriptStep{command: :end_map_event, datalong: @quest, datalong2: 1} = finish] =
               sprite_event.sub_scripts[sprite_event.dataint2]

      assert finish.condition == %Condition{type: :map_event_active, value1: @quest}

      assert [
               %ScriptStep{command: :movement, datalong: 0},
               %ScriptStep{command: :quest_explored, datalong: @quest, datalong2: 100, datalong3: 1},
               %ScriptStep{command: :talk, dataint: 4_080},
               %ScriptStep{command: :despawn, delay_ms: 30_000}
             ] = quest_event.sub_scripts[quest_event.dataint2]

      assert [
               %ScriptStep{command: :fail_quest, datalong: @quest},
               %ScriptStep{command: :talk, dataint: 5_285},
               %ScriptStep{command: :end_map_event, datalong: @sprite_event, datalong2: 0},
               %ScriptStep{command: :respawn_creature}
             ] = quest_event.sub_scripts[quest_event.dataint4]
    end

    test "a sixth sprite lost fails the quest with Kindal's own words instead of the timeout's" do
      %{@quest => [_quest_event, sprite_event | _steps]} = CreatureScript.quest_start_steps()

      assert sprite_event.failure_condition ==
               %Condition{type: :map_event_data, value1: @sprite_event, value2: 1, value3: 6, value4: 1}

      assert [
               %ScriptStep{command: :talk, dataint: 4_081},
               %ScriptStep{command: :fail_quest, datalong: @quest},
               %ScriptStep{command: :edit_map_event, datalong: @quest, dataint: -1, dataint4: quiet} = edit,
               %ScriptStep{command: :end_map_event, datalong: @quest, datalong2: 0}
             ] = steps = sprite_event.sub_scripts[sprite_event.dataint4]

      assert Enum.all?(steps, &(&1.condition == %Condition{type: :map_event_active, value1: @quest}))

      assert [%ScriptStep{command: :movement, datalong: 0}, %ScriptStep{command: :despawn, delay_ms: 30_000}] =
               edit.sub_scripts[quiet]
    end
  end

  defp leaves([%ScriptStep{command: :start_script} = step]) do
    step |> ScriptStep.start_script_options() |> Enum.flat_map(fn {id, _chance} -> leaves(step.sub_scripts[id]) end)
  end

  defp leaves([%ScriptStep{} = step]), do: [step]
end
