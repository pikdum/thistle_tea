defmodule ThistleTea.Game.Core.AI.CreatureScript.BlackrockSpireTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @omokk 9_196
  @voone 9_237
  @wyrmthalak 9_568
  @halycon 10_220
  @the_beast 10_430
  @blackhand_veteran 9_819

  describe "events/1" do
    test "Omokk stomps, strikes, rends, sunders, knocks away and slows on his own timers" do
      timers = for %{event_type: :timer_in_combat} = event <- CreatureScript.events(@omokk), do: timer(event)

      assert timers == [
               {24_375, :self, 15_000, 14_000},
               {18_368, :victim, 10_000, 10_000},
               {18_106, :victim, 14_000, 18_000},
               {24_317, :victim, 2_000, 25_000},
               {20_686, :self, 18_000, 12_000},
               {22_356, :self, 24_000, 18_000}
             ]
    end

    test "Voone throws one axe, then the other, and fights barehanded after" do
      [first, second] =
        Enum.filter(CreatureScript.events(@voone), fn event ->
          match?([[%ScriptStep{datalong: 16_075} | _]], event.actions)
        end)

      assert first.inverse_phase_mask == CreatureScript.only_in_phases([0])
      assert [[_throw, keep_one, %ScriptStep{command: :set_phase, datalong: 1}]] = first.actions
      assert %ScriptStep{command: :set_equipment, dataint: 12_348, dataint2: 0, dataint3: -1} = keep_one

      assert second.inverse_phase_mask == CreatureScript.only_in_phases([1])
      assert [[_throw, empty, unarmed, %ScriptStep{command: :set_phase, datalong: 2}]] = second.actions
      assert %ScriptStep{command: :set_equipment, dataint: 0, dataint2: 0} = empty
      assert %ScriptStep{command: :cast_spell, datalong: 16_076, target_self?: true} = unarmed

      assert [
               %{
                 actions: [
                   [%ScriptStep{command: :set_equipment, datalong: 1}, %ScriptStep{command: :set_phase, datalong: 0}]
                 ]
               }
             ] =
               Enum.filter(CreatureScript.events(@voone), &(&1.event_type == :evade))
    end

    test "Wyrmthalak calls a warlord and a berserker once at half health" do
      assert [%{param1: 51, repeatable?: false, actions: [summons]}] =
               Enum.filter(CreatureScript.events(@wyrmthalak), &(&1.event_type == :hp))

      assert [9_216, 9_268] = Enum.map(summons, & &1.datalong)

      for summon <- summons do
        assert %ScriptStep{command: :summon_creature, datalong2: 10_000, dataint3: 4, dataint4: 4} = summon
      end
    end

    test "Halycon's death howls for Gizrul, who comes for the whole party" do
      assert [%{actions: [[howl, gizrul]], repeatable?: false}] =
               Enum.filter(CreatureScript.events(@halycon), &(&1.event_type == :death))

      assert [%{chat_type: :text_emote, text: "Halycon lets loose a gutteral growl" <> _rest}] = howl.texts
      assert %ScriptStep{command: :summon_creature, datalong: 10_268, dataint2: 1, dataint3: -1, dataint4: 7} = gizrul

      assert %{1 => [%ScriptStep{command: :set_home_position}, %ScriptStep{command: :zone_combat_pulse}]} =
               gizrul.sub_scripts
    end

    test "The Beast keeps its fiery aura and charges its victim before anyone else" do
      events = CreatureScript.events(@the_beast)

      for type <- [:spawned, :reached_home] do
        assert [%{actions: [[%ScriptStep{datalong: 15_506, target_self?: true}]]}] =
                 Enum.filter(events, &(&1.event_type == type))
      end

      charges = Enum.filter(events, &match?([[%ScriptStep{datalong: 16_636}]], &1.actions))
      assert [%{param1: 0, repeatable?: false}, %{param1: 15_000, param2: 20_000}] = charges

      assert [[[%{target_type: :victim}]], [[%{target_type: :hostile_random_not_top}]]] =
               Enum.map(charges, & &1.actions)
    end

    test "a Blackhand Veteran opens with a shield charge at its victim" do
      assert [first | _rest] = CreatureScript.events(@blackhand_veteran)
      assert %{param1: 0, repeatable?: false, actions: [[%ScriptStep{datalong: 15_749, target_type: :victim}]]} = first
    end
  end

  defp timer(%{actions: [[%ScriptStep{datalong: spell} = step]], param1: first, param3: repeat}) do
    {spell, if(step.target_self?, do: :self, else: step.target_type), first, repeat}
  end
end
