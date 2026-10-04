defmodule ThistleTea.Game.Core.AI.CreatureScript.StormwindRendezvousTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Quest.QuestLog.Entry

  @rowe 17_804
  @windsor 12_580
  @windsor_up %Condition{type: :map_event_active, value1: 6_402}

  describe "gossip/0" do
    test "Squire Rowe signals Windsor for a player fresh from the rendezvous while Windsor is away" do
      %Gossip{texts: texts, options: [signal]} = Map.fetch!(CreatureScript.gossip(), @rowe)

      assert Enum.map(texts, & &1.text_id) == [9_063, 9_065, 9_064, 9_066]
      assert signal.text == "Let Marshal Windsor know that I am ready."

      for {quests, rewarded, windsor_up?, text_id, signal?} <- [
            {[], [], false, 9_063, false},
            {[{6_402, :complete}], [], false, 9_065, true},
            {[], [6_402], true, 9_064, false},
            {[{6_403, :incomplete}], [6_402], false, 9_065, true},
            {[], [6_402, 6_403], false, 9_066, false}
          ] do
        context = context(quests, rewarded, windsor_up?)
        assert shown(texts, context) == text_id
        assert Condition.evaluate(context, signal.condition) == if(signal?, do: :met, else: :unmet)
      end

      assert [
               %ScriptStep{command: :start_map_event, datalong: 6_402, abort_on_failure?: true},
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x1, datalong3: 2},
               %ScriptStep{command: :set_run, datalong: 1},
               %ScriptStep{command: :move_to, datalong3: 5, datalong4: 2, dataint: 1}
             ] = signal.steps
    end

    test "Windsor marches on the keep at the word of a player on the masquerade" do
      %Gossip{texts: [%Gossip.Text{text_id: 5_633}], options: [ready]} = Map.fetch!(CreatureScript.gossip(), @windsor)

      assert %Condition{
               type: :and,
               children: [
                 %Condition{type: :quest_taken, value1: 6_403, value2: 1},
                 %Condition{type: :map_event_active, value1: 6_403}
               ]
             } = ready.condition

      assert [
               %ScriptStep{command: :talk, dataint: 8_208},
               %ScriptStep{command: :modify_flags, datalong: 147, datalong3: 2},
               %ScriptStep{command: :start_waypoints, datalong: 5, dataint3: 2}
             ] = ready.steps
    end
  end

  describe "events/1" do
    test "Rowe kneels on the road, lights the flare, and calls Windsor riding for the gates" do
      [to_road, signal, home] = CreatureScript.events(@rowe)

      assert {to_road.param1, to_road.param2} == {9, 1}
      assert [%ScriptStep{command: :move_to, datalong4: 2, dataint: 2}] = hd(to_road.actions)
      assert [%ScriptStep{command: :emote, datalong: 16}, %ScriptStep{sub_scripts: %{1 => called}}] = hd(signal.actions)

      assert %ScriptStep{datalong: 181_987, datalong2: 10, delay_ms: 5_000} =
               Enum.find(called, &(&1.command == :summon_object))

      assert %ScriptStep{datalong: @windsor, dataint4: 8, position: {-9_148.40, 371.32, 91.0, 0.70}} =
               summon =
               Enum.find(called, &(&1.command == :summon_creature))

      assert [
               %ScriptStep{command: :add_map_event_target, datalong: 6_402, dataint4: cleanup, sub_scripts: scripts},
               %ScriptStep{command: :mount, datalong: 2_410, datalong2: 1},
               %ScriptStep{command: :modify_flags, datalong: 147, datalong2: 0x2, datalong3: 2},
               %ScriptStep{command: :set_run, datalong: 1},
               %ScriptStep{command: :move_to, datalong4: 2, dataint: 1}
             ] = summon.sub_scripts[1]

      assert [%ScriptStep{command: :despawn}] = scripts[cleanup]
      assert {home.param1, home.param2} == {9, 4}
      assert [_face, %ScriptStep{datalong2: 0x1, datalong3: 1}, %ScriptStep{dataint: 14_389}] = hd(home.actions)
    end

    test "Windsor greets the player who called him and leaves if no one takes the masquerade" do
      [arrived, idle, _finale] = CreatureScript.events(@windsor)

      [_home, %ScriptStep{sub_scripts: %{1 => greeting}}] = hd(arrived.actions)

      assert %ScriptStep{command: :cast_spell, datalong: 20_000, target_self?: true} =
               Enum.find(greeting, &(&1.command == :cast_spell))

      assert %ScriptStep{target_type: :map_event_target, target_param1: 6_402, delay_ms: 12_000} =
               Enum.find(greeting, &(&1.dataint == 8_090))

      assert Enum.any?(greeting, &match?(%ScriptStep{command: :set_phase, datalong: 1}, &1))

      assert {idle.event_type, idle.param1, idle.param3} == {:timer_ooc, 300_000, 0}
      assert idle.inverse_phase_mask == CreatureScript.only_in_phases([1])
      assert [[%ScriptStep{command: :end_map_event, datalong: 6_402, datalong2: 0}]] = idle.actions
    end

    test "once no elite guard stands, Bolvar mourns, the masquerade is credited, and Windsor dies" do
      [_arrived, _idle, finale] = CreatureScript.events(@windsor)

      assert finale.inverse_phase_mask == CreatureScript.only_in_phases([3])
      assert %Condition{type: :nearby_creature, value1: 12_739, reverse?: true} = finale.condition
      assert [[%ScriptStep{command: :set_phase, datalong: 4}, %ScriptStep{sub_scripts: %{1 => steps}}]] = finale.actions

      credit = Enum.find_index(steps, &(&1.command == :quest_explored))
      ends = steps |> Enum.with_index() |> Enum.filter(&(elem(&1, 0).command == :end_map_event))
      death = Enum.find_index(steps, &(&1.command == :deal_damage))

      assert %ScriptStep{datalong: 6_403, datalong3: 1, target_type: :map_event_target} = Enum.at(steps, credit)
      assert Enum.map(ends, &{elem(&1, 0).datalong, elem(&1, 0).datalong2}) == [{6_403, 1}, {6_402, 1}]
      assert Enum.at(steps, credit).delay_ms < Enum.at(steps, death).delay_ms
      assert Enum.all?(ends, &(elem(&1, 1) < death))
    end
  end

  describe "quest_start_steps/0" do
    test "taking the masquerade starts its escort event and lines the bridge with guards" do
      [event | steps] = Map.fetch!(CreatureScript.quest_start_steps(), 6_403)

      assert %ScriptStep{
               command: :start_map_event,
               datalong: 6_403,
               abort_on_failure?: true,
               failure_condition: %Condition{type: :escort, value1: 1, value2: 100},
               dataint4: failure
             } = event

      assert [
               %ScriptStep{command: :fail_quest, datalong: 6_403},
               %ScriptStep{command: :end_map_event, datalong: 6_402, datalong2: 0}
             ] = event.sub_scripts[failure]

      %ScriptStep{sub_scripts: %{1 => opening}} = List.last(steps)
      guards = Enum.filter(opening, &match?(%ScriptStep{command: :summon_creature, datalong: 68}, &1))

      assert length(guards) == 6
      assert Enum.all?(guards, &(&1.dataint4 == 3 and &1.datalong2 == 240_000))

      assert %ScriptStep{sub_scripts: %{1 => voice}} =
               Enum.find(opening, &match?(%ScriptStep{command: :summon_creature, datalong: 1_749}, &1))

      assert [%ScriptStep{command: :morph, datalong: 11_686}, _unselectable, %ScriptStep{dataint: 8_119}] = voice
      assert Enum.any?(opening, &match?(%ScriptStep{command: :start_waypoints, datalong: 5, dataint3: 1}, &1))
    end
  end

  describe "routes/0" do
    test "Windsor talks Marcus down at the bridge, then walks to the keep's doorstep" do
      [procession, keep] = CreatureScript.routes() |> Enum.filter(&(&1.entry == @windsor))

      assert {procession.variant, keep.variant} == {1, 2}
      assert length(procession.path) == 18
      assert {_x, _y, _z, 87_700} = hd(procession.path)
      assert {_x, _y, _z, 0} = List.last(procession.path)

      kneel = Enum.find(procession.points[0], &match?(%ScriptStep{command: :start_script_for_all, datalong3: 68}, &1))
      lines = kneel.sub_scripts[1]

      assert length(lines) == 6
      assert Enum.all?(lines, &match?(%Condition{type: :distance_to_position, swap_targets?: true}, &1.condition))

      assert %ScriptStep{sub_scripts: %{1 => [move, face, %ScriptStep{command: :stand_state, datalong: 8}]}} =
               hd(lines)

      assert {move.delay_ms, face.delay_ms} == {0, 1_000 + 2_233}

      assert for(point <- 2..17, do: salute_entries(procession.points[point])) ==
               List.duplicate([68, 1_976, 1_756], 16)

      assert Enum.any?(procession.points[16], &match?(%ScriptStep{command: :talk, dataint: 8_207}, &1))
      assert Enum.any?(procession.points[16], &match?(%ScriptStep{command: :modify_flags, datalong2: 0x1}, &1))
    end

    test "in the throne room the tablets unmask Prestor and her royal guards turn" do
      [_procession, keep] = CreatureScript.routes() |> Enum.filter(&(&1.entry == @windsor))
      scene = keep.points[4]

      assert %ScriptStep{datalong: 20_358, target_param1: 1_749, delay_ms: 55_000} =
               Enum.find(scene, &(&1.command == :cast_spell))

      assert %ScriptStep{datalong: 12_756, target_param1: 1_749, swap_final?: true} =
               Enum.find(scene, &(&1.command == :update_entry))

      unmask = Enum.find(scene, &match?(%ScriptStep{command: :start_script_for_all, target_param1: 12_756}, &1))
      assert %ScriptStep{datalong3: 1_756, datalong4: 25} = unmask
      assert [%ScriptStep{command: :update_entry, datalong: 12_739} | _] = unmask.sub_scripts[1]

      assert %ScriptStep{command: :set_phase, datalong: 3, delay_ms: 103_400} = List.last(scene)
    end
  end

  describe "summon_entries/0" do
    test "the procession's summons are preloaded" do
      assert Enum.all?([12_580, 68, 1_749], &(&1 in CreatureScript.summon_entries()))
      assert Enum.all?([12_756, 12_739], &(&1 in CreatureScript.creature_entries()))
    end
  end

  defp salute_entries(steps) do
    steps
    |> Enum.filter(&match?(%ScriptStep{command: :start_script_for_all, datalong4: 10}, &1))
    |> Enum.map(& &1.datalong3)
  end

  defp shown(texts, context) do
    texts
    |> Enum.filter(&(is_nil(&1.condition) or Condition.evaluate(context, &1.condition) == :met))
    |> List.last()
    |> Map.fetch!(:text_id)
  end

  defp context(quests, rewarded, windsor_up?) do
    quest_log =
      quests
      |> Enum.with_index()
      |> Map.new(fn {{quest_id, status}, slot} -> {slot, %Entry{quest_id: quest_id, status: status}} end)

    results = %{
      @windsor_up => Condition.Result.truth(windsor_up?),
      %{@windsor_up | reverse?: true} => Condition.Result.truth(not windsor_up?)
    }

    Context.new(
      target: Subject.new(quest_log: quest_log, rewarded_quests: MapSet.new(rewarded)),
      environment: %{condition_results: results}
    )
  end
end
