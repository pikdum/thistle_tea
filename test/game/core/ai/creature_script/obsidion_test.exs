defmodule ThistleTea.Game.Core.AI.CreatureScript.ObsidionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @obsidion 8_400
  @dorius 8_421
  @lathoric 8_391

  describe "quest_start_steps/0" do
    test "taking the quest has Obsidion call Dorius to the scene" do
      [scene] = CreatureScript.quest_start_steps()[3_566]

      assert %ScriptStep{
               command: :start_script,
               target_type: :nearest_creature_with_entry,
               target_param1: @obsidion,
               swap_final?: true
             } = scene

      assert [%ScriptStep{command: :summon_creature, datalong: @dorius, datalong2: 180_000, dataint4: 1}] =
               scene.sub_scripts[scene.datalong]
    end

    test "Dorius speaks, unmasks as Lathoric, and sets Obsidion on the nearest player" do
      steps = dorius_scene()

      assert Enum.map(Enum.take(steps, 6), &{&1.dataint, &1.delay_ms}) == [
               {4_393, 5_000},
               {4_394, 11_000},
               {4_395, 17_000},
               {4_396, 23_000},
               {4_397, 29_000},
               {4_398, 35_000}
             ]

      assert %ScriptStep{command: :update_entry, datalong: @lathoric, delay_ms: 36_000} = Enum.at(steps, 6)

      rally = Enum.drop(steps, 7)
      assert Enum.all?(rally, &(&1.delay_ms == 41_000))
      assert %ScriptStep{command: :talk, dataint: 4_391} = hd(rally)

      assert [:stand_state, :modify_flags, :start_script] =
               rally |> Enum.filter(&(&1.target_param1 == @obsidion and &1.swap_final?)) |> Enum.map(& &1.command)

      assert %ScriptStep{command: :attack_start, target_type: :nearest_hostile_player} = List.last(rally)
    end
  end

  describe "events/1" do
    test "Obsidion rests out of reach and fights with smashes and knockbacks" do
      events = CreatureScript.events(@obsidion)

      assert [:spawned, :evade, :reached_home, :aggro, :timer_in_combat, :timer_in_combat] =
               Enum.map(events, & &1.event_type)

      assert [[%ScriptStep{command: :stand_state, datalong: 7}, immune]] = hd(events).actions
      assert %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: 1} = immune

      assert [12_734, 10_101] =
               events |> Enum.filter(&(&1.event_type == :timer_in_combat)) |> Enum.map(&hd(hd(&1.actions)).datalong)
    end
  end

  defp dorius_scene do
    [scene] = CreatureScript.quest_start_steps()[3_566]
    [summon] = scene.sub_scripts[scene.datalong]
    [timed] = summon.sub_scripts[summon.dataint2]
    timed.sub_scripts[timed.datalong]
  end
end
