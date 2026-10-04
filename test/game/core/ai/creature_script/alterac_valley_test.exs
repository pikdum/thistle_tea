defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @vanndar 11_948
  @drek_thar 11_946
  @balinda 11_949
  @galvangar 11_947
  @leashed 1

  describe "events/1" do
    test "every leader gives up the fight when drawn out of their keep" do
      for {entry, x, radius} <- [
            {@vanndar, 722.4, 35},
            {@drek_thar, -1_370.9, 33},
            {@balinda, -57.7, 45},
            {@galvangar, -545.2, 45}
          ] do
        assert [%{param1: 1_000, param3: 1_000, check_result?: false, condition: away, actions: [steps]}] =
                 entry |> CreatureScript.events() |> Enum.filter(&leash?/1)

        assert %Condition{type: :distance_to_position, value1: ^x, value4: ^radius} = away
        assert %Condition{swap_targets?: true, reverse?: true} = away

        assert %ScriptStep{command: :enter_evade} = List.last(steps)
      end
    end

    test "a general shouts one taunt when pulled out and another when his attackers fall" do
      for {entry, leashed, wiped} <- [{@vanndar, 10_373, 10_374}, {@drek_thar, 10_377, 10_376}] do
        assert {0, [^leashed]} = evade(entry, @leashed)
        assert {0, [^wiped]} = evade(entry, 0)
      end
    end

    test "a general's defenders join in against his victim" do
      vanndar = CreatureScript.events(@vanndar)
      drek_thar = CreatureScript.events(@drek_thar)

      assert rallied(vanndar) == [13_333 | Enum.to_list(14_762..14_769)]
      assert rallied(drek_thar) == [12_121, 12_122 | Enum.to_list(14_770..14_777)]

      [rally | _] = rallies(vanndar)
      assert %ScriptStep{datalong2: 2, datalong4: 100} = rally

      assert [%ScriptStep{command: :attack_start, condition: %Condition{type: :and, children: idle}}] =
               sub_script(rally)

      assert [%Condition{type: :alive, swap_targets?: true}, %Condition{type: :in_combat, reverse?: true}] = idle
    end

    test "Drek'Thar raises his fallen wolves when he resets" do
      assert [%{actions: [raises]}] =
               @drek_thar
               |> CreatureScript.events()
               |> Enum.filter(&(&1.event_type == :evade and &1.inverse_phase_mask == 0))

      assert Enum.map(raises, & &1.datalong3) == [12_121, 12_122]
      assert Enum.all?(raises, &(sub_script(&1) == [%ScriptStep{command: :respawn_creature}]))
    end

    test "Balinda holds her ground while her victim is in sight at casting range" do
      events = CreatureScript.events(@balinda)

      assert [%{condition: casting_spot}] =
               Enum.filter(events, &match?(%{actions: [[%{datalong: 0, command: :set_combat_movement}]]}, &1))

      assert [%{condition: chasing}] =
               Enum.filter(events, &match?(%{actions: [[%{datalong: 1, command: :set_combat_movement}]]}, &1))

      assert %Condition{
               type: :and,
               reverse?: false,
               children: [_at_least_five, _at_most_twenty_five, %{type: :line_of_sight}]
             } =
               casting_spot

      assert chasing == %{casting_spot | reverse?: true}
    end

    test "Balinda polymorphs her second attacker and saves her cone and explosion for close targets" do
      events = CreatureScript.events(@balinda)

      assert %{param1: 1_750} = cast(events, 15_534, target_type: :hostile_second_aggro)
      assert %{condition: %Condition{type: :distance_to_target, value1: 10, value2: 2}} = cast(events, 22_746)
      assert %{condition: %Condition{type: :distance_to_target, value1: 6, value2: 2}} = cast(events, 19_712)
    end

    test "a warmaster charges from range and whirlwinds twice in a row" do
      for entry <- [14_762, 14_777] do
        events = CreatureScript.events(entry)

        assert %{param1: 0, condition: %Condition{type: :and, children: [eight, twenty_five]}} = cast(events, 22_911)
        assert {eight.value1, eight.value2, twenty_five.value1, twenty_five.value2} == {8, 1, 25, 2}

        assert [%{param1: 12_000, actions: [[%ScriptStep{datalong: 13_736}, again]]}] =
                 Enum.filter(events, &match?(%{actions: [[%ScriptStep{datalong: 13_736} | _]]}, &1))

        assert [%ScriptStep{datalong: 13_736, delay_ms: 2_000}] = sub_script(again)
      end
    end
  end

  defp leash?(%{actions: [steps]}), do: Enum.any?(steps, &match?(%ScriptStep{command: :enter_evade}, &1))

  defp rallies(events) do
    Enum.find_value(events, fn %{actions: [steps]} ->
      if Enum.all?(steps, &match?(%ScriptStep{command: :start_script_for_all}, &1)) and length(steps) > 2, do: steps
    end)
  end

  defp rallied(events), do: events |> rallies() |> Enum.map(& &1.datalong3)

  defp sub_script(%ScriptStep{sub_scripts: sub_scripts}) do
    [steps] = Map.values(sub_scripts)
    steps
  end

  defp cast(events, spell_id, step_fields \\ []) do
    Enum.find(events, fn %{actions: [steps]} -> Enum.any?(steps, &casts?(&1, spell_id, step_fields)) end)
  end

  defp casts?(%ScriptStep{command: :cast_spell, datalong: spell_id} = step, spell_id, step_fields),
    do: Enum.all?(step_fields, fn {field, value} -> Map.fetch!(step, field) == value end)

  defp casts?(_step, _spell_id, _step_fields), do: false

  defp evade(entry, phase) do
    general = general(entry)
    blackboard = Blackboard.new()
    blackboard = %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}

    {general, blackboard} = EventAI.on_evade(general, blackboard, 1_000)

    shouts = for %Effects.MonsterTalk{text: text} <- general.internal.events, do: String.to_integer(text)
    {blackboard.event_ai.phase, shouts}
  end

  defp general(entry) do
    events =
      entry
      |> CreatureScript.events()
      |> Enum.filter(&(&1.event_type == :evade))
      |> Enum.map(fn event -> %{event | actions: Enum.map(event.actions, &voiced/1)} end)

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, level: 62, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(30), creature: %Creature{ai_events: events}, spellbook: %{}}
    }
  end

  defp voiced(steps) do
    Enum.map(steps, fn
      %ScriptStep{command: :talk, dataint: text_id} = step ->
        %{step | texts: [%{text: Integer.to_string(text_id), chat_type: :zone_yell, language: 0, emote_id: 0}]}

      step ->
        step
    end)
  end
end
