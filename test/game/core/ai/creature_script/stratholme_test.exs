defmodule ThistleTea.Game.Core.AI.CreatureScript.StratholmeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @barthilas 10_435
  @anastari 10_436
  @nerubenkan 10_437
  @maleki 10_438
  @ramstein 10_439
  @timmy 10_808
  @dathrohan 10_812
  @willey 10_997
  @malown 11_143

  describe "events/1" do
    test "Barthilas stacks Furious Anger and restarts his blows whether or not they land" do
      timers = Enum.filter(CreatureScript.events(@barthilas), &(&1.event_type == :timer_in_combat))

      assert Enum.map(timers, &timer/1) == [
               {16_791, :self, 5_000, 4_000},
               {16_793, :victim, 16_000, 15_000},
               {10_887, :victim, 12_000, 15_000},
               {14_099, :victim, 8_000, 20_000}
             ]

      refute Enum.any?(timers, & &1.check_result?)
    end

    test "Anastari curses only a victim not already cursed" do
      assert %{actions: [[%ScriptStep{datalong: 16_867, datalong2: 0x20}]], param1: 11_000, check_result?: true} =
               Enum.find(CreatureScript.events(@anastari), &(&1.param1 == 11_000))
    end

    test "Nerub'enkan raises a swarm of crypt scarabs or one undead scarab against a random attacker" do
      assert [%{actions: [[%ScriptStep{command: :start_script} = raise]], param1: 3_000, param3: 6_000}] =
               Enum.filter(CreatureScript.events(@nerubenkan), &(&1.param1 == 3_000))

      scarabs =
        for {id, chance} <- options(raise),
            id > 0,
            [summon] = Map.fetch!(raise.sub_scripts, id),
            do: {summon.datalong, summon.count, chance}

      assert scarabs == [{10_577, 4, 16}, {10_577, 6, 16}, {10_577, 8, 16}, {10_876, 1, 52}]

      for [summon] <- Map.values(raise.sub_scripts) do
        assert %ScriptStep{dataint3: 4, dataint4: 4, scatter: 10.0, datalong2: 10_000} = summon
      end
    end

    test "Maleki holds his ground until hurt, then closes in to drain mana from casters or life from the rest" do
      events = CreatureScript.events(@maleki)
      assert [%{actions: [[%ScriptStep{command: :set_combat_movement, datalong: 0}]]}] = by_type(events, :aggro)

      assert [mana, life] = by_type(events, :hp)
      assert %{param1: 60, condition: %Condition{type: :mana_percent, value1: 1, value2: 1}} = mana
      assert %{param1: 60, condition: %Condition{type: :race_class, value2: 0x9}} = life

      for {drain, spell_id} <- [{mana, 17_243}, {life, 17_238}] do
        assert [[%ScriptStep{command: :set_phase, datalong: 1}, %ScriptStep{datalong: ^spell_id}]] = drain.actions
      end

      reaches =
        for %{event_type: :range, actions: [[step]]} = event <- events,
            do: {event.param1, event.param2, step.datalong, event.inverse_phase_mask}

      assert reaches == [
               {0, 40, 0, CreatureScript.only_in_phases([0])},
               {40, 500, 1, CreatureScript.only_in_phases([0])},
               {0, 20, 0, CreatureScript.only_in_phases([1])},
               {20, 500, 1, CreatureScript.only_in_phases([1])}
             ]

      assert [%{actions: [[%ScriptStep{command: :set_phase, datalong: 0}]]}] = by_type(events, :evade)
    end

    test "Ramstein's Knockout wipes his victim's threat only once it lands" do
      assert %{actions: [[knockout, wipe]], check_result?: true} =
               Enum.find(CreatureScript.events(@ramstein), &(&1.param1 == 12_000))

      assert %ScriptStep{datalong: 17_307, abort_on_failure?: true} = knockout
      assert %ScriptStep{command: :modify_threat, datalong: 1, position: {-100.0, _, _, _}} = wipe
    end

    test "Timmy enrages once below a tenth of his health" do
      assert [%{param1: 10, repeatable?: false, actions: [[%ScriptStep{datalong: 8_599, target_self?: true}]]}] =
               by_type(CreatureScript.events(@timmy), :hp)
    end

    test "Dathrohan becomes Balnazzar at 40 percent and reverts if he leaves the fight" do
      events = CreatureScript.events(@dathrohan)

      assert [%{param1: 40, repeatable?: false, actions: [transform]}] = by_type(events, :hp)

      assert [
               %ScriptStep{command: :interrupt_casts},
               %ScriptStep{datalong: 17_288, datalong2: 0x02, target_self?: true},
               %ScriptStep{command: :update_entry, datalong: 10_813},
               %ScriptStep{command: :creature_spells, datalong: 0},
               %ScriptStep{command: :set_phase, datalong: 1},
               %ScriptStep{sub_scripts: %{1 => later}}
             ] = transform

      assert [%ScriptStep{command: :talk, dataint: 6_447, delay_ms: 4_000} | sends] = later
      assert Enum.map(sends, &{&1.datalong, &1.delay_ms}) == [{1, 7_000}, {2, 13_000}, {3, 16_000}, {4, 22_000}]

      dathrohan_only =
        for %{inverse_phase_mask: mask} = event <- events, mask == CreatureScript.only_in_phases([0]), do: timer(event)

      assert dathrohan_only == [
               {17_286, :self, 8_000, 12_000},
               {17_281, :victim, 12_000, 15_000},
               {17_284, :victim, 18_000, 15_000}
             ]

      assert [%{actions: [[_phase, %ScriptStep{command: :update_entry, datalong: @dathrohan}, _clear]]}] =
               by_type(events, :evade)
    end

    test "Balnazzar's shadow magic repeats on his vmangos timers and dominates his second-highest threat" do
      chains = Map.new(by_type(CreatureScript.events(@dathrohan), :script_event), &{&1.param1, hd(&1.actions)})

      for {event_id, spell_id, repeat_ms} <- [{1, 17_399, 11_000}, {2, 12_098, 15_000}, {3, 13_704, 20_000}] do
        assert [%ScriptStep{datalong: ^spell_id}, %ScriptStep{sub_scripts: %{1 => [resend]}}] =
                 Map.fetch!(chains, event_id)

        assert %ScriptStep{command: :send_script_event, datalong: ^event_id, delay_ms: ^repeat_ms} = resend
      end

      assert [%ScriptStep{datalong: 12_098, target_type: :hostile_random_not_top} | _] = Map.fetch!(chains, 2)
      assert [%ScriptStep{datalong: 17_405, target_type: :hostile_second_aggro} | _] = Map.fetch!(chains, 4)
    end

    test "Dathrohan's death raises a skeleton of either kind at each of 32 posts" do
      assert [%{actions: [[%ScriptStep{command: :talk, dataint: 6_442} | raised]]}] =
               by_type(CreatureScript.events(@dathrohan), :death)

      assert length(raised) == 32

      for %ScriptStep{command: :start_script, sub_scripts: kinds} <- raised do
        assert kinds |> Map.values() |> Enum.map(fn [summon] -> summon.datalong end) |> Enum.sort() == [10_390, 10_391]
      end
    end

    test "Willey calls three riflemen to one of nine spot patterns every ten seconds" do
      assert %{actions: [[%ScriptStep{command: :start_script} = call]], param1: 5_000, param3: 10_000} =
               Enum.find(CreatureScript.events(@willey), &(&1.param1 == 5_000 and &1.param2 == 5_000))

      patterns = riflemen_patterns(call)
      assert length(patterns) == 9

      for riflemen <- patterns do
        assert length(riflemen) == 3

        for rifleman <- riflemen do
          assert %ScriptStep{
                   datalong: 11_054,
                   dataint4: 4,
                   sub_scripts: %{1 => [%ScriptStep{command: :zone_combat_pulse}]}
                 } =
                   rifleman
        end
      end

      assert patterns |> List.flatten() |> Enum.map(& &1.position) |> Enum.frequencies() |> Map.values() ==
               List.duplicate(3, 9)
    end

    test "Malown's curses are chance rolls on fixed timers" do
      events = CreatureScript.events(@malown)
      assert [%{actions: [[%ScriptStep{dataint: 6_504}]]}] = by_type(events, :aggro)
      assert [%{actions: [[%ScriptStep{dataint: 6_530}]]}] = by_type(events, :kill)

      rolls = for %{event_type: :timer_in_combat} = event <- events, do: {hd(hd(event.actions)).datalong, event.chance}
      assert rolls == [{7_713, 65}, {6_253, 45}, {8_552, 3}, {12_889, 3}, {17_831, 5}]
      refute Enum.any?(events, & &1.check_result?)
    end
  end

  defp by_type(events, type), do: Enum.filter(events, &(&1.event_type == type))

  defp options(%ScriptStep{} = step),
    do: [
      {step.datalong, step.dataint},
      {step.datalong2, step.dataint2},
      {step.datalong3, step.dataint3},
      {step.datalong4, step.dataint4}
    ]

  defp riflemen_patterns(%ScriptStep{sub_scripts: sub_scripts}) do
    Enum.flat_map(Map.values(sub_scripts), fn
      [%ScriptStep{command: :summon_creature} | _] = riflemen -> [riflemen]
      steps -> Enum.flat_map(steps, &riflemen_patterns/1)
    end)
  end

  defp timer(%{actions: [[%ScriptStep{datalong: spell} = step]], param1: first, param3: repeat}) do
    {spell, if(step.target_self?, do: :self, else: step.target_type), first, repeat}
  end
end
