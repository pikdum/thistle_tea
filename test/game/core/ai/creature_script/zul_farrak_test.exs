defmodule ThistleTea.Game.Core.AI.CreatureScript.ZulFarrakTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @bly 7_604
  @weegli 7_607

  describe "events/1" do
    test "Weegli starts the waves on reaching the stairs, or on getting home while the cages stand open" do
      [arrived, home, watch | _rest] = CreatureScript.events(@weegli)

      assert %{event_type: :movement_inform, param1: 9, param2: 1} = arrived
      assert %{event_type: :reached_home, condition: %Condition{type: :instance_data, value1: 1, value2: 1}} = home
      assert arrived.actions == home.actions

      assert [
               %ScriptStep{command: :talk, dataint: 3_744},
               %ScriptStep{command: :set_instance_data, datalong: 1, datalong2: 2, datalong3: 0},
               %ScriptStep{command: :set_home_position},
               %ScriptStep{command: :move_to, datalong3: 5, datalong4: 2, dataint: 2}
             ] = hd(arrived.actions)

      assert %{event_type: :movement_inform, param2: 2} = watch
    end

    test "Weegli plants a charge, sets it off from cover, and leaves" do
      [_arrived, _home, _watch, at_door, clear, gone, bomb | home_again] = CreatureScript.events(@weegli)

      assert [
               [
                 %ScriptStep{command: :summon_object, datalong: 144_065, datalong2: 300},
                 %ScriptStep{command: :set_home_position},
                 %ScriptStep{command: :move_to, dataint: 11}
               ]
             ] = at_door.actions

      assert [
               [
                 %ScriptStep{command: :set_game_object_state, datalong: 0, target_param1: 144_065},
                 %ScriptStep{command: :set_instance_data, datalong: 3, datalong2: 3},
                 %ScriptStep{command: :set_home_position},
                 %ScriptStep{command: :move_to, dataint: 12}
               ]
             ] = clear.actions

      assert %{param2: 12, actions: [[%ScriptStep{command: :despawn}]]} = gone
      assert %{event_type: :timer_in_combat, actions: [[%ScriptStep{command: :cast_spell, datalong: 8_858}]]} = bomb

      assert Enum.map(home_again, &{&1.event_type, &1.condition.value1, &1.actions}) == [
               {:reached_home, 1_858.57, at_door.actions},
               {:reached_home, 1_863.77, clear.actions},
               {:reached_home, 1_827.1, gone.actions}
             ]

      assert Enum.all?(home_again, &match?(%Condition{type: :distance_to_position, swap_targets?: true}, &1.condition))
    end

    test "Bly bashes and takes revenge" do
      assert spells(@bly) == [11_972, 12_170]
    end

    test "a Ward of Zum'rah raises a skeleton every five seconds, fighting or not" do
      events = CreatureScript.events(7_785)

      assert Enum.map(events, & &1.event_type) == [:timer_ooc, :timer_in_combat]
      assert Enum.all?(events, &({&1.param1, &1.param2, &1.param3, &1.param4} == {5_000, 5_000, 5_000, 5_000}))
      assert spells(7_785) == [11_088, 11_088]
    end
  end

  describe "gossip/0" do
    test "Bly turns on the player and sets the crew on them once the trolls are dead" do
      %Gossip{texts: texts, options: [fight]} = Map.fetch!(CreatureScript.gossip(), @bly)

      assert Enum.map(texts, & &1.text_id) == [1_516, 1_515, 1_517]
      assert %Condition{type: :instance_data, value1: 1, value2: 8} = fight.condition

      assert [
               %ScriptStep{command: :talk, dataint: 3_882, delay_ms: 0},
               %ScriptStep{command: :talk, dataint: 3_884, delay_ms: 5_000},
               %ScriptStep{command: :talk, dataint: 3_811, target_param1: @weegli, swap_final?: true},
               %ScriptStep{command: :start_script, target_param1: @weegli, swap_final?: true} | turn
             ] = fight.steps

      assert Enum.map(turn, &{&1.command, &1.datalong, &1.target_param1, &1.target_type, &1.delay_ms}) == [
               {:set_faction, 35, 7_605, :nearest_creature_with_entry, 10_000},
               {:set_faction, 35, 7_606, :nearest_creature_with_entry, 10_000},
               {:set_faction, 35, 7_608, :nearest_creature_with_entry, 10_000},
               {:set_faction, 35, 0, :provided, 10_000},
               {:set_faction, 14, 7_605, :nearest_creature_with_entry, 10_000},
               {:set_faction, 14, 7_606, :nearest_creature_with_entry, 10_000},
               {:set_faction, 14, 7_608, :nearest_creature_with_entry, 10_000},
               {:set_faction, 14, 0, :provided, 10_000},
               {:attack_start, 0, 0, :provided, 10_000}
             ]
    end

    test "Weegli runs for the end door once the trolls are dead" do
      %Gossip{texts: texts, options: [door]} = Map.fetch!(CreatureScript.gossip(), @weegli)

      assert Enum.map(texts, & &1.text_id) == [1_513, 1_511, 1_514]

      assert [
               %ScriptStep{command: :set_faction, datalong: 35},
               %ScriptStep{command: :talk, dataint: 3_785},
               %ScriptStep{command: :set_home_position, position: {1_858.57, 1_146.35, 14.745, _}},
               %ScriptStep{command: :move_to, datalong3: 5, datalong4: 2, dataint: 10}
             ] = door.steps
    end
  end

  defp spells(entry) do
    entry
    |> CreatureScript.events()
    |> Enum.flat_map(&List.flatten(&1.actions))
    |> Enum.map(& &1.datalong)
  end
end
