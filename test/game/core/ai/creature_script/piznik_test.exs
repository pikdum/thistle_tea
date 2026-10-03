defmodule ThistleTea.Game.Core.AI.CreatureScript.PiznikTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @piznik 4_276
  @gerenzos_orders 1_090

  describe "quest_start_steps/0" do
    test "accepting the quest opens Piznik to attack and sends three waves at him" do
      steps = Map.fetch!(CreatureScript.quest_start_steps(), @gerenzos_orders)

      assert [
               %ScriptStep{command: :start_map_event, datalong: @gerenzos_orders, abort_on_failure?: true},
               %ScriptStep{command: :set_phase, datalong: 1},
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x1000, datalong3: 1},
               %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x200, datalong3: 2},
               %ScriptStep{command: :set_faction, datalong: 495, datalong2: 1},
               %ScriptStep{command: :start_script, sub_scripts: %{1 => timed}}
             ] = steps

      summons = Enum.filter(timed, &(&1.command == :summon_creature))
      assert Enum.all?(summons, &(&1.dataint3 == 8))

      assert Enum.map(summons, &{&1.delay_ms, &1.datalong}) == [
               {1_000, 3_998},
               {1_000, 4_001},
               {60_000, 3_998},
               {60_000, 4_001},
               {60_000, 3_998},
               {120_000, 3_998},
               {120_000, 4_001},
               {120_000, 4_003}
             ]
    end

    test "the waves and the credit only come while the defense is under way" do
      %ScriptStep{sub_scripts: %{1 => timed}} =
        CreatureScript.quest_start_steps() |> Map.fetch!(@gerenzos_orders) |> List.last()

      assert Enum.all?(timed, &(&1.condition == %Condition{type: :map_event_active, value1: @gerenzos_orders}))

      assert %ScriptStep{delay_ms: 180_000, datalong3: 1, target_type: :map_event_target} =
               Enum.find(timed, &(&1.command == :quest_explored))

      assert %ScriptStep{command: :end_map_event, delay_ms: 180_000} = List.last(timed)
    end
  end

  describe "events/1" do
    test "Piznik's death during the defense fails the quest" do
      assert [death] = CreatureScript.events(@piznik)
      assert %{event_type: :death, inverse_phase_mask: mask} = death
      assert mask == CreatureScript.only_in_phases([1])

      assert [
               %ScriptStep{command: :fail_quest, datalong: @gerenzos_orders, target_type: :map_event_target},
               %ScriptStep{command: :end_map_event, datalong: @gerenzos_orders}
             ] = List.flatten(death.actions)
    end
  end
end
