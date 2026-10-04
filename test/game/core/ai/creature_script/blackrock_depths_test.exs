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

  defp timer(%{actions: [[%ScriptStep{datalong: spell} = step]], param1: first, param3: repeat}) do
    {spell, if(step.target_self?, do: :self, else: step.target_type), first, repeat}
  end
end
