defmodule ThistleTea.Game.Core.AI.CreatureScript.BlackrockDepthsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @gerstahn 9_018
  @grizzle 9_028
  @angerforge 9_033
  @doomrel 9_039
  @plugger 9_499
  @emperor 9_019
  @moira 8_929

  describe "events/1" do
    test "Gerstahn burns mana and pains random foes and screams at his victim" do
      timers = for %{event_type: :timer_in_combat} = event <- CreatureScript.events(@gerstahn), do: timer(event)

      assert timers == [
               {14_032, :hostile_random, 4_000, 7_000},
               {14_033, :hostile_random, 14_000, 10_000},
               {13_704, :victim, 32_000, 30_000},
               {12_040, :self, 8_000, 25_000}
             ]
    end

    test "Grizzle frenzies every fifteen seconds once below half health" do
      assert [%{param1: 51, param3: 15_000, repeatable?: true, actions: [[frenzy, emote]]}] =
               Enum.filter(CreatureScript.events(@grizzle), &(&1.event_type == :hp))

      assert %ScriptStep{datalong: 8_269, target_self?: true} = frenzy
      assert %ScriptStep{command: :talk, dataint: 7_797} = emote
    end

    test "Angerforge's alarm calls eight reservists and two medics every three minutes" do
      assert [%{param1: 30, param3: 180_000, actions: [[alarm | reserves]]}] =
               Enum.filter(CreatureScript.events(@angerforge), &(&1.event_type == :hp))

      assert %ScriptStep{command: :talk, dataint: 5_286} = alarm
      assert reserves |> Enum.map(& &1.datalong) |> Enum.frequencies() == %{8_901 => 8, 8_894 => 2}
      assert Enum.all?(reserves, &match?(%ScriptStep{command: :summon_creature, dataint3: 4, dataint4: 2}, &1))
    end

    test "Doom'rel calls his voidwalkers once at half health" do
      assert [%{param1: 50, repeatable?: false, actions: [[%ScriptStep{datalong: 15_092, datalong2: 0x02}]]}] =
               Enum.filter(CreatureScript.events(@doomrel), &(&1.event_type == :hp))
    end

    test "Plugger keeps his demon armor up and grumbles between fights" do
      assert [armor, grumble] = Enum.filter(CreatureScript.events(@plugger), &(&1.event_type == :timer_ooc))
      assert [[%ScriptStep{datalong: 13_787, target_self?: true}]] = armor.actions
      assert [[%ScriptStep{command: :talk, dataint: 5_310, dataint4: 5_309}]] = grumble.actions
      assert %{param1: 10_000, param3: 30_000, param4: 35_000} = grumble
    end

    test "the Emperor rallies the throne room and his death leaves Moira shaken" do
      events = CreatureScript.events(@emperor)

      assert [%{actions: [[_aggro_yell, %ScriptStep{command: :call_for_help, position: {166.0, _, _, _}}]]}] =
               Enum.filter(events, &(&1.event_type == :aggro))

      assert [%{actions: [[faction, evade, shaken]]}] = Enum.filter(events, &(&1.event_type == :death))
      assert %ScriptStep{command: :set_faction, datalong: 35} = faction
      assert %ScriptStep{command: :enter_evade} = evade
      assert %ScriptStep{command: :talk, dataint: 5_429} = shaken

      for step <- [faction, evade, shaken] do
        assert %ScriptStep{target_type: :nearest_creature_with_entry, target_param1: @moira, swap_final?: true} = step
      end
    end

    test "Moira mends injured allies between her shadow spells" do
      assert %{actions: [[%ScriptStep{datalong: 15_586, target_type: :friendly_injured, target_param1: 40}]]} =
               Enum.find(CreatureScript.events(@moira), &(&1.param1 == 12_000))
    end
  end

  describe "routes/0" do
    test "Grimstone opens the beast gate and calls two packs of one random kind each" do
      [%{1 => [_line, %ScriptStep{sub_scripts: %{1 => timed}}]}] = grimstone_points()

      assert [%ScriptStep{command: :set_instance_data, datalong: 46, datalong2: 1, delay_ms: 7_000} | _rest] = timed
      [first_pack, second_pack] = Enum.filter(timed, &(&1.command == :start_script))
      assert first_pack.delay_ms == 10_000
      assert second_pack.delay_ms == 29_000

      for pack <- [first_pack, second_pack] do
        kinds = chosen(pack)

        assert Enum.sort(Enum.map(kinds, fn summons -> hd(summons).datalong end)) == [
                 8_925,
                 8_926,
                 8_927,
                 8_928,
                 8_932,
                 8_933
               ]

        for summons <- kinds do
          assert Enum.map(summons, & &1.delay_ms) == [0, 3_000, 3_000, 7_000]
          assert summons |> Enum.map(& &1.datalong) |> Enum.uniq() |> length() == 1

          for summon <- summons do
            assert %ScriptStep{dataint4: 7, position: {608.96, -235.322, _, _}} = summon

            assert %{1 => [%ScriptStep{command: :set_home_position}, %ScriptStep{command: :zone_combat_pulse}]} =
                     summon.sub_scripts
          end
        end
      end
    end

    test "Grimstone calls one of the six champions and closes the ring once it falls" do
      [%{4 => [%ScriptStep{dataint: 5_446}, %ScriptStep{sub_scripts: %{1 => timed}}], 5 => [done]}] = grimstone_points()

      assert [%ScriptStep{datalong: 46, datalong2: 2, delay_ms: 5_000}, _teleport, champion] = timed
      champions = champion |> chosen() |> Enum.map(fn [summon] -> summon.datalong end)
      assert Enum.sort(champions) == [9_027, 9_028, 9_029, 9_030, 9_031, 9_032]
      assert %ScriptStep{command: :set_instance_data, datalong: 0, datalong2: 3} = done
    end
  end

  defp grimstone_points, do: for(%{entry: 10_096, points: points} <- CreatureScript.routes(), do: points)

  defp chosen(%ScriptStep{sub_scripts: sub_scripts}) do
    Enum.flat_map(Map.values(sub_scripts), fn steps ->
      case Enum.filter(steps, &(&1.command == :summon_creature)) do
        [] -> Enum.flat_map(steps, &chosen/1)
        summons -> [summons]
      end
    end)
  end

  defp timer(%{actions: [[%ScriptStep{datalong: spell} = step]], param1: first, param3: repeat}) do
    {spell, if(step.target_self?, do: :self, else: step.target_type), first, repeat}
  end
end
