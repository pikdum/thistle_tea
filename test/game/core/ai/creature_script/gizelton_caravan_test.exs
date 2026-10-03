defmodule ThistleTea.Game.Core.AI.CreatureScript.GizeltonCaravanTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @cork 11_625
  @rigger 11_626
  @kodo 11_564
  @bottom 5_943
  @top 5_821

  describe "events/1" do
    test "two seconds after spawning Cork calls up the caravan and sets off on his path" do
      [spawned | _] = CreatureScript.events(@cork)
      assert spawned.event_type == :spawned

      assert [%ScriptStep{command: :start_script, sub_scripts: %{1 => setup}}] = List.flatten(spawned.actions)
      assert Enum.all?(setup, &(&1.delay_ms == 2_000))

      assert [
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0xFFFF_FFFF, datalong3: 2},
               %ScriptStep{command: :summon_creature, datalong: @kodo},
               %ScriptStep{command: :summon_creature, datalong: @rigger} = rigger,
               %ScriptStep{command: :summon_creature, datalong: @kodo},
               %ScriptStep{command: :start_waypoints, datalong: 5}
             ] = setup

      assert [
               %ScriptStep{
                 command: :join_creature_group,
                 datalong: 0x3,
                 position: {18.0, +0.0, +0.0, 3.14},
                 target_type: :nearest_creature_with_entry,
                 target_param1: @cork
               },
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 2}
             ] = rigger.sub_scripts[rigger.dataint2]
    end

    test "the caravan disbands when Cork, Rigger, or a kodo dies" do
      events = CreatureScript.events(@cork) |> tl()

      assert Enum.map(events, &{&1.event_type, &1.param1}) == [
               {:summoned_just_died, @rigger},
               {:summoned_just_died, @kodo},
               {:death, 0}
             ]

      for event <- events do
        assert [
                 %ScriptStep{command: :end_map_event, datalong: @bottom, datalong2: 0},
                 %ScriptStep{command: :end_map_event, datalong: @top, datalong2: 0},
                 %ScriptStep{command: :start_script_on_group, sub_scripts: %{1 => [%ScriptStep{command: :despawn}]}}
               ] = List.flatten(event.actions)
      end
    end
  end

  describe "routes/0" do
    test "the giver offers the quest and yells to the zone every three minutes while it is offered" do
      [hold, give | yells] = point(14)
      assert length(yells) == 5

      assert %ScriptStep{command: :modify_flags, datalong3: 1, target_param1: @rigger, swap_final?: true} = give
      assert Enum.map(yells, & &1.delay_ms) == [0, 180_000, 360_000, 540_000, 720_000]

      for yell <- yells do
        assert %ScriptStep{command: :talk, dataint: 7_475, datalong: 6, target_param1: @rigger} = yell
        assert yell.condition == %Condition{type: :has_flag, value1: 147, value2: 0x2}
      end

      assert %ScriptStep{command: :hold_waypoints, datalong: 900_000, datalong2: 1} = hold

      assert [
               %ScriptStep{command: :modify_flags, datalong3: 2, target_param1: @rigger},
               %ScriptStep{command: :start_script_on_group, sub_scripts: %{1 => depart}}
             ] = hold.sub_scripts[1]

      assert [%ScriptStep{command: :set_faction, datalong: 495}, %ScriptStep{datalong2: 0x200, datalong3: 2}] = depart
    end

    test "Cork offers the top leg himself" do
      [_hold, give | _yells] = point(164)
      assert %ScriptStep{command: :modify_flags, target_type: :provided, swap_final?: false} = give
    end

    test "an escorted leg is ambushed and the caravan waits for the ambushers to die" do
      steps = point(173)
      escorted = %Condition{type: :map_event_active, value1: @top}

      assert Enum.all?(steps, &(&1.condition == escorted))
      assert %ScriptStep{command: :hold_waypoints, datalong2: 0} = hd(steps)
      assert %ScriptStep{command: :talk, dataint: 7_310, target_type: :provided} = List.last(steps)

      summons = Enum.filter(steps, &(&1.command == :summon_creature))
      assert Enum.map(summons, & &1.datalong) == [12_977, 12_976, 12_977, 12_976]
      assert Enum.map(summons, &{&1.dataint3, &1.target_param1}) == [{8, 0}, {28, @kodo}, {10, @rigger}, {28, @kodo}]
      assert Enum.all?(summons, &(length(&1.positions) == 8 and &1.dataint4 == 1 and &1.datalong2 == 30_000))
    end

    test "finishing a leg credits the player nearby and puts the caravan back at peace" do
      assert [
               %ScriptStep{command: :talk, dataint: 7_333, target_param1: @rigger},
               %ScriptStep{command: :quest_explored, datalong: @bottom, datalong2: 100, target_type: :map_event_target},
               %ScriptStep{command: :end_map_event, datalong: @bottom, datalong2: 1},
               %ScriptStep{command: :start_script_on_group, sub_scripts: %{1 => peace}},
               %ScriptStep{command: :set_run, datalong: 1}
             ] = point(42)

      assert [%ScriptStep{command: :set_faction, datalong: 0}, %ScriptStep{datalong2: 0x200, datalong3: 1}] = peace
    end

    test "the caravan camps for ten minutes while its vendor trades" do
      assert [
               %ScriptStep{command: :set_run, datalong: 0},
               %ScriptStep{command: :hold_waypoints, datalong: 600_000, datalong2: 1} = hold,
               %ScriptStep{command: :set_concealed, datalong: 0, target_param1: 12_245, swap_final?: true}
             ] = point(141)

      assert [
               %ScriptStep{command: :talk, dataint: 7_505, target_type: :provided},
               %ScriptStep{command: :set_concealed, datalong: 1, target_param1: 12_245}
             ] = hold.sub_scripts[1]

      assert [_walk, %ScriptStep{sub_scripts: %{1 => [leave, _hide]}}, %ScriptStep{target_param1: 12_246}] = point(279)
      assert %ScriptStep{dataint: 7_506, target_param1: @rigger} = leave
    end

    test "the caravan despawns at the end of its path" do
      assert [%ScriptStep{command: :start_script_on_group, sub_scripts: %{1 => [%ScriptStep{command: :despawn}]}}] =
               point(281)
    end
  end

  describe "quest_start_steps/0" do
    test "accepting either leg starts its event and sends the caravan off ten seconds later" do
      %{@bottom => [forward], @top => top} = CreatureScript.quest_start_steps()

      assert %ScriptStep{command: :start_script_for_all, datalong2: 2, datalong3: @cork, datalong4: 100} = forward
      bottom = forward.sub_scripts[forward.datalong]

      for {quest, steps} <- [{@bottom, bottom}, {@top, top}] do
        assert [
                 %ScriptStep{command: :start_map_event, datalong: ^quest, abort_on_failure?: true} = event,
                 %ScriptStep{command: :modify_flags, datalong3: 2},
                 %ScriptStep{command: :release_waypoints, delay_ms: 10_000}
               ] = steps

        assert event.failure_condition == %Condition{type: :escort, value1: 1}
        assert [%ScriptStep{command: :fail_quest, datalong: ^quest}] = event.sub_scripts[event.dataint4]
      end
    end
  end

  defp point(point), do: CreatureScript.routes() |> Map.fetch!(@cork) |> Map.fetch!(point)
end
