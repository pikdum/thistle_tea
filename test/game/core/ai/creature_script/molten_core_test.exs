defmodule ThistleTea.Game.Core.AI.CreatureScript.MoltenCoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @lucifron 12_118
  @gehennas 12_259
  @shazzrah 12_264
  @garr 12_057
  @firesworn 12_099
  @geddon 12_056
  @sulfuron 12_098
  @golemagg 11_988
  @core_rager 11_672

  describe "events/1" do
    test "most lieutenants pull the whole raid into the fight" do
      for entry <- [@lucifron, @gehennas, @garr, @firesworn, @geddon, @sulfuron] do
        assert [%{actions: [steps]}] = by_type(CreatureScript.events(entry), :aggro)
        assert Enum.any?(steps, &match?(%ScriptStep{command: :zone_combat_pulse}, &1))
      end

      for entry <- [@shazzrah, @golemagg], do: assert(by_type(CreatureScript.events(entry), :aggro) == [])
    end

    test "Lucifron dooms and curses the raid and shocks a random attacker" do
      assert Enum.map(by_type(CreatureScript.events(@lucifron), :timer_in_combat), &timer/1) == [
               {19_702, :self, 10_000, 20_000},
               {19_703, :self, 20_000, 15_000},
               {19_460, :hostile_random, 6_000, 6_000}
             ]
    end

    test "Shazzrah blinks to a random player, forgets all threat, and attacks them" do
      blink = Enum.find(CreatureScript.events(@shazzrah), &(&1.param1 == 25_000))

      assert %{param2: 30_000, param3: 25_000, param4: 35_000, actions: [[gate, start]]} = blink
      assert %ScriptStep{datalong: 23_138, datalong2: 0x02, target_self?: true} = gate
      assert %ScriptStep{command: :start_script, target_type: :hostile_random, target_param1: 0x2} = start

      assert [
               %ScriptStep{command: :teleport_to, at_target?: true, target_type: :provided},
               %ScriptStep{command: :modify_threat, datalong: 8, position: {-100.0, _, _, _}},
               %ScriptStep{command: :attack_start, target_type: :provided}
             ] = only_sub_script(start)
    end

    test "Garr enrages as his Firesworn die and forces one to erupt every twenty seconds after six minutes" do
      events = CreatureScript.events(@garr)

      assert [%{param1: 19_515, actions: [[%ScriptStep{datalong: 19_516, target_self?: true}]]}] =
               by_type(events, :hit_by_spell)

      assert %{param3: 20_000, check_result?: false, actions: [[erupt]]} = Enum.find(events, &(&1.param1 == 360_000))
      assert %ScriptStep{target_type: :random_creature_with_entry, target_param1: @firesworn} = erupt

      assert [%ScriptStep{command: :talk, dataint: 8_254}, %ScriptStep{datalong: 20_482, target_type: :provided}] =
               only_sub_script(erupt)
    end

    test "a Firesworn erupts as it dies, unless Garr already made it erupt" do
      events = CreatureScript.events(@firesworn)

      assert [%{param1: 20_482, actions: [[%ScriptStep{command: :set_phase, datalong: 1}, massive]]}] =
               by_type(events, :hit_by_spell)

      assert %ScriptStep{datalong: 20_483, target_self?: true} = massive

      assert [enrage, eruption] = by_type(events, :death)
      assert %{inverse_phase_mask: 0, actions: [[%ScriptStep{datalong: 19_515, target_param1: @garr}]]} = enrage

      assert %{inverse_phase_mask: mask, actions: [[%ScriptStep{datalong: 19_497}]]} = eruption
      assert mask == CreatureScript.only_in_phases([0])
    end

    test "Baron Geddon stops everything for Armageddon below five percent" do
      events = CreatureScript.events(@geddon)
      fighting = CreatureScript.only_in_phases([0])

      assert [{20_475, :hostile_random, _, _}, {19_659, :self, _, _}, {19_695, :self, _, _}] =
               Enum.map(by_type(events, :timer_in_combat), &timer/1)

      assert Enum.all?(by_type(events, :timer_in_combat), &(&1.inverse_phase_mask == fighting))

      assert [%{param1: 5, repeatable?: false, inverse_phase_mask: ^fighting, actions: [armageddon]}] =
               by_type(events, :hp)

      assert [
               %ScriptStep{command: :interrupt_casts},
               %ScriptStep{command: :set_combat_movement, datalong: 0},
               %ScriptStep{datalong: 20_478, datalong2: 0x02},
               %ScriptStep{command: :talk, dataint: 8_253},
               %ScriptStep{command: :set_phase, datalong: 1}
             ] = armageddon
    end

    test "Sulfuron inspires a nearby priest and then himself" do
      assert %{actions: [[priest, self_cast]]} = Enum.find(CreatureScript.events(@sulfuron), &(&1.param1 == 13_000))
      assert %ScriptStep{target_type: :random_creature_with_entry, target_param1: 11_662, target_param2: 45} = priest
      assert [%ScriptStep{datalong: 19_779, datalong2: 0x02}] = only_sub_script(priest)
      assert %ScriptStep{datalong: 19_779, target_self?: true} = self_cast
    end

    test "Golemagg calls his ragers below a tenth of his health and quakes every five seconds until he evades" do
      events = CreatureScript.events(@golemagg)

      assert [%{param1: 10, repeatable?: false, actions: [[attract, later]]}] = by_type(events, :hp)
      assert %ScriptStep{datalong: 20_544, target_self?: true} = attract
      assert [%ScriptStep{command: :send_script_event, datalong: 1, delay_ms: 5_000}] = only_sub_script(later)

      assert [%{param1: 1, actions: [[%ScriptStep{datalong: 19_798}, again]]}] = by_type(events, :script_event)
      assert only_sub_script(again) == only_sub_script(later)
      assert [%{actions: [[%ScriptStep{command: :stop_scripts}]]}] = by_type(events, :evade)
    end

    test "a Core Rager will not drop below half health while Golemagg lives" do
      events = CreatureScript.events(@core_rager)

      assert [%{actions: [[%ScriptStep{command: :invincibility, datalong: 50, datalong2: 1}]]}] =
               by_type(events, :spawned)

      assert [%{param1: 50, condition: master_alive, actions: [[talk, heal]]}] = by_type(events, :hp)
      assert %Condition{type: :instance_data, value1: 3, value2: 2, value3: 2} = master_alive
      assert %ScriptStep{command: :talk, dataint: 7_865} = talk
      assert %ScriptStep{datalong: 17_683, target_self?: true} = heal
    end
  end

  defp by_type(events, type), do: Enum.filter(events, &(&1.event_type == type))

  defp only_sub_script(%ScriptStep{sub_scripts: sub_scripts}) do
    [steps] = Map.values(sub_scripts)
    steps
  end

  defp timer(%{actions: [[%ScriptStep{datalong: spell} = step]], param1: first, param3: repeat}) do
    {spell, if(step.target_self?, do: :self, else: step.target_type), first, repeat}
  end
end
