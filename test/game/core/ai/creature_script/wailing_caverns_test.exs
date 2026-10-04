defmodule ThistleTea.Game.Core.AI.CreatureScript.WailingCavernsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @disciple 3_678
  @ectoplasm 3_640
  @ready %Condition{type: :instance_data, value1: 4, value2: 4}

  describe "gossip/0" do
    test "the disciple offers to begin only once the Fanglords are dead" do
      assert %{@disciple => %Gossip{texts: [greeting, ready], options: [option]}} = CreatureScript.gossip()

      assert %Gossip.Text{text_id: 698, condition: nil} = greeting
      assert %Gossip.Text{text_id: 699, condition: @ready} = ready
      assert %Gossip.Option{text: "Let the event begin!", condition: @ready, steps: steps} = option

      assert [
               %ScriptStep{command: :start_map_event, datalong: @disciple},
               %ScriptStep{command: :set_faction, datalong: 250},
               %ScriptStep{command: :modify_flags},
               %ScriptStep{command: :set_run, datalong: 0},
               %ScriptStep{command: :set_phase, datalong: 1},
               %ScriptStep{command: :start_waypoints, datalong: 5, datalong2: 0}
             ] = steps
    end
  end

  describe "routes/0" do
    test "the disciple holds at each scene until it plays out" do
      assert [%Route{path: path, points: points}] = Enum.filter(CreatureScript.routes(), &(&1.entry == @disciple))

      assert length(path) == 32

      assert path
             |> Enum.with_index()
             |> Enum.filter(fn {{_, _, _, wait}, _} -> wait > 60_000 end)
             |> Enum.map(&elem(&1, 1)) ==
               [7, 15, 30]

      assert points |> Map.keys() |> Enum.sort() == [0, 7, 15, 26, 30]
    end

    test "the ritual summons Mutanus last, after the moccasins and ectoplasms" do
      [%Route{points: %{30 => ritual}}] = Enum.filter(CreatureScript.routes(), &(&1.entry == @disciple))
      [%ScriptStep{sub_scripts: %{1 => timed}}] = Enum.filter(ritual, &(&1.command == :start_script))

      summons =
        for %ScriptStep{command: :summon_creature, datalong: entry, delay_ms: delay} <- timed, do: {delay, entry}

      assert summons |> Enum.uniq() |> Enum.sort() == [{12_000, 5_762}, {52_000, 5_763}, {102_000, 3_654}]
      assert Enum.count(summons, &match?({_, 5_763}, &1)) == 7
    end
  end

  describe "events/1" do
    test "Naralex wakes after Mutanus dies whether or not the disciple is still fighting" do
      slain =
        Enum.filter(
          CreatureScript.events(@disciple),
          &match?(%Condition{type: :instance_data, value1: 5}, &1.condition)
        )

      assert slain |> Enum.map(& &1.event_type) |> Enum.sort() == [:timer_in_combat, :timer_ooc]

      assert Enum.all?(
               slain,
               &(&1.condition.value2 == 3 and &1.inverse_phase_mask == CreatureScript.only_in_phases([6]))
             )
    end

    test "the ritual fails when the disciple dies" do
      assert [%{actions: [[%ScriptStep{command: :end_map_event, datalong: @disciple, datalong2: 0}]]}] =
               Enum.filter(CreatureScript.events(@disciple), &(&1.event_type == :death))
    end

    test "an evolving ectoplasm takes on the colour of the school that strikes it" do
      frost = Enum.find(CreatureScript.events(@ectoplasm), &(&1.event_type == :hit_by_spell and &1.param2 == 16))

      assert %{actions: [[transform, immunity, %ScriptStep{command: :set_phase, datalong: 1}, restore]]} = frost
      assert %ScriptStep{command: :cast_spell, datalong: 7_944, target_self?: true} = transform
      assert %ScriptStep{command: :cast_spell, datalong: 7_940, target_self?: true} = immunity
      assert %ScriptStep{command: :start_script, sub_scripts: %{1 => [%ScriptStep{delay_ms: 10_000} | _]}} = restore
    end
  end
end
