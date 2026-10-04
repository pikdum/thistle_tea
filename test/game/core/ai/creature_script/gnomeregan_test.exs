defmodule ThistleTea.Game.Core.AI.CreatureScript.GnomereganTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @emi 7_998
  @grubbis 7_361
  @chomper 6_215
  @thermaplugg 7_800

  describe "gossip/0" do
    test "Emi offers to begin while Grubbis has not been beaten" do
      assert %{@emi => %Gossip{texts: [], options: [option]}} = CreatureScript.gossip()
      assert %Gossip.Option{text: "I am ready to begin.", condition: condition, steps: steps} = option

      assert %Condition{type: :or, children: children} = condition
      assert Enum.map(children, &{&1.type, &1.value1, &1.value2}) == [{:instance_data, 0, 0}, {:instance_data, 0, 2}]

      assert [
               %ScriptStep{command: :start_map_event, datalong: @emi},
               %ScriptStep{command: :set_instance_data, datalong: 0, datalong2: 1},
               %ScriptStep{command: :start_script, sub_scripts: %{1 => intro}}
             ] = steps

      assert %ScriptStep{command: :start_waypoints, datalong: 5, datalong2: 0, delay_ms: 9_500} = List.last(intro)
      assert Enum.any?(intro, &match?(%ScriptStep{command: :set_faction, datalong: 113}, &1))
    end
  end

  describe "routes/0" do
    test "Emi holds at each scene until it plays out" do
      assert [%Route{path: path, points: points}] = Enum.filter(CreatureScript.routes(), &(&1.entry == @emi))

      assert length(path) == 19
      assert {_, _, _, 5_000} = Enum.at(path, 3)

      assert path
             |> Enum.with_index()
             |> Enum.filter(fn {{_, _, _, wait}, _} -> wait > 60_000 end)
             |> Enum.map(&elem(&1, 1)) == [8, 10, 12, 14, 15, 16, 18]

      assert points |> Map.keys() |> Enum.sort() == [3, 8, 10, 12, 14, 15, 16, 18]
    end

    test "she will not fight while she plants a charge" do
      for {point, charge} <- [{10, 1}, {12, 2}, {15, 3}, {16, 4}] do
        assert [react, %ScriptStep{command: :emote, datalong: 69}, %ScriptStep{sub_scripts: %{1 => timed}}] =
                 point_steps(point)

        assert %ScriptStep{command: :set_react_state, datalong: 0} = react
        assert [planted] = for(%ScriptStep{command: :set_instance_data, datalong: 2} = step <- timed, do: step)
        assert planted.datalong2 == charge

        assert %ScriptStep{command: :set_react_state, datalong: 2, delay_ms: delay} =
                 Enum.find(timed, &(&1.command == :set_react_state))

        assert delay == planted.delay_ms
        assert %ScriptStep{command: :start_waypoints, datalong2: next} = List.last(timed)
        assert next == point + 1
      end
    end

    test "troggs pour toward the open cave-in, and Grubbis and Chomper wait below" do
      summons =
        [8, 10, 12, 14, 15, 16, 18]
        |> Enum.flat_map(&timed_steps/1)
        |> Enum.filter(&(&1.command == :summon_creature))

      assert length(summons) == 33
      assert Enum.all?(summons, &(&1.dataint3 == -1 and &1.dataint4 == 7))

      {bosses, troggs} = Enum.split_with(summons, &(&1.datalong in [@grubbis, @chomper]))
      assert Enum.map(bosses, & &1.datalong) == [@grubbis, @chomper]

      assert Enum.all?(
               summons,
               &match?(
                 %ScriptStep{sub_scripts: %{1 => [%ScriptStep{command: :add_map_event_target, datalong: @emi} | _]}},
                 &1
               )
             )

      assert Enum.all?(bosses, &match?(%ScriptStep{sub_scripts: %{1 => [_target]}}, &1))

      assert Enum.all?(
               troggs,
               &match?(%ScriptStep{sub_scripts: %{1 => [_target, %ScriptStep{command: :move_to, datalong: 3}]}}, &1)
             )
    end

    test "she blows the southern tunnel shut before opening the northern one" do
      timed = timed_steps(14)
      at = fn command, field -> Enum.find(timed, &(&1.command == command and &1.datalong == field)).delay_ms end

      assert %ScriptStep{command: :cast_spell, datalong: 12_159, delay_ms: blast} =
               Enum.find(timed, &(&1.command == :cast_spell))

      assert at.(:set_instance_data, 3) > blast
      assert Enum.find(timed, &(&1.command == :set_instance_data and &1.datalong == 2)).datalong2 == 5
      assert at.(:set_instance_data, 4) > at.(:set_instance_data, 3)
      assert %ScriptStep{command: :start_waypoints, datalong2: 15} = List.last(timed)
    end
  end

  describe "events/1" do
    test "Grubbis's death sets off the northern charges and the fireworks" do
      assert [%{actions: [[phase, %ScriptStep{sub_scripts: %{1 => timed}}]]} = slain] =
               Enum.filter(CreatureScript.events(@emi), &(&1.event_type == :summoned_just_died))

      assert slain.param1 == @grubbis
      assert slain.inverse_phase_mask == CreatureScript.only_in_phases([2])
      assert %ScriptStep{command: :set_phase, datalong: 3} = phase

      assert timed |> Enum.filter(&(&1.command == :cast_spell)) |> Enum.map(& &1.datalong) == [12_158, 11_542]
      assert %ScriptStep{command: :end_map_event, datalong: @emi, datalong2: 1} = List.last(timed)
    end

    test "the event fails when Emi dies" do
      assert [%{actions: [[%ScriptStep{command: :end_map_event, datalong: @emi, datalong2: 0}]]}] =
               Enum.filter(CreatureScript.events(@emi), &(&1.event_type == :death))
    end

    test "Thermaplugg knocks away his target, then everyone around him from half health" do
      events = CreatureScript.events(@thermaplugg)
      first_half = CreatureScript.only_in_phases([0])
      second_half = CreatureScript.only_in_phases([1])

      knocks =
        for %{event_type: :timer_in_combat, actions: [[%ScriptStep{datalong: spell} | _]]} = event <- events,
            spell in [10_101, 11_130],
            do: {spell, event.inverse_phase_mask}

      assert knocks == [{10_101, first_half}, {11_130, second_half}]

      assert [%{repeatable?: false, param1: 50, actions: [[_say, %ScriptStep{command: :set_phase, datalong: 1}]]}] =
               Enum.filter(events, &(&1.event_type == :hp))

      assert [%{actions: [[%ScriptStep{command: :set_phase, datalong: 0}]]}] =
               Enum.filter(events, &(&1.event_type == :evade))
    end

    test "each bomb Thermaplugg activates opens one of the six faces at random" do
      bombs =
        for %{event_type: :timer_in_combat, actions: [[%ScriptStep{datalong: spell} | rest]]} = event <-
              CreatureScript.events(@thermaplugg),
            spell in [11_511, 11_795],
            do: {spell, event.param3, event.param4, rest}

      assert [{11_511, 12_000, 17_000, [pick, _say]}, {11_795, 6_000, 12_000, _}] = bombs

      fields =
        for {_id, steps} <- nested(pick), %ScriptStep{command: :set_instance_data} = step <- steps do
          {step.datalong, step.datalong2}
        end

      assert Enum.sort(fields) == Enum.map(10..15, &{&1, 1})
    end
  end

  defp nested(%ScriptStep{command: :start_script, sub_scripts: scripts}) do
    Enum.flat_map(scripts, fn {id, steps} ->
      case steps do
        [%ScriptStep{command: :start_script} = inner] -> nested(inner)
        steps -> [{id, steps}]
      end
    end)
  end

  defp point_steps(point) do
    [%Route{points: points}] = Enum.filter(CreatureScript.routes(), &(&1.entry == @emi))
    Map.fetch!(points, point)
  end

  defp timed_steps(point) do
    [%ScriptStep{sub_scripts: %{1 => timed}}] = Enum.filter(point_steps(point), &(&1.command == :start_script))
    timed
  end
end
