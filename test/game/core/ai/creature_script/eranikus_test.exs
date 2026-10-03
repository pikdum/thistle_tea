defmodule ThistleTea.Game.Core.AI.CreatureScript.EranikusTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Eranikus
  alias ThistleTea.Game.Core.AI.ScriptStep

  @remulos 11_832
  @eranikus 15_491
  @tyrande 15_633

  describe "events/1" do
    test "Eranikus hovers out of reach and joins the quest's event to clean up after a failure" do
      %{actions: [steps]} = find(@eranikus, :spawned)

      assert %ScriptStep{command: :add_aura, datalong: 17_131} = Enum.find(steps, &(&1.command == :add_aura))
      assert %ScriptStep{datalong2: 0x2, datalong3: 1} = Enum.find(steps, &(&1.command == :modify_flags))
      assert %ScriptStep{datalong: 20, datalong2: 1} = Enum.find(steps, &(&1.command == :invincibility))

      assert %ScriptStep{datalong: 8736, dataint4: script_id, sub_scripts: scripts} =
               Enum.find(steps, &(&1.command == :add_map_event_target))

      cleanup = Map.fetch!(scripts, script_id)
      assert %ScriptStep{command: :despawn} = List.last(cleanup)

      assert cleanup |> Enum.filter(&(&1.command == :start_script_for_all)) |> Enum.map(& &1.datalong3) ==
               [15_633, 15_634, 15_629]
    end

    test "Eranikus answers Remulos's signals by flying up and then landing to fight" do
      %{actions: [[fly_up]]} = find(@eranikus, :script_event, &(&1.param1 == Eranikus.fly_up()))
      assert %ScriptStep{command: :move_to, datalong3: 0x0C, dataint: flight_point} = fly_up

      %{actions: [[face]]} = find(@eranikus, :movement_inform, &(&1.param2 == flight_point))
      assert %ScriptStep{command: :turn_to, target_param1: @remulos} = face

      %{actions: [[unhover, descend]]} = find(@eranikus, :script_event, &(&1.param1 == Eranikus.descend()))
      assert %ScriptStep{command: :remove_aura, datalong: 17_131} = unhover

      %{actions: [landing]} = find(@eranikus, :movement_inform, &(&1.param2 == descend.dataint))
      assert %ScriptStep{command: :set_fly, datalong: 0} = hd(landing)
      assert Enum.any?(landing, &match?(%ScriptStep{command: :talk, dataint: 11_305}, &1))

      [%ScriptStep{command: :start_script, sub_scripts: %{1 => engage}}] =
        Enum.filter(landing, &(&1.command == :start_script))

      assert Enum.any?(engage, &match?(%ScriptStep{command: :attack_start, target_param1: @remulos}, &1))
    end

    test "Eranikus breathes and casts volleys only while he fights, and fails the quest if he evades" do
      timers = @eranikus |> CreatureScript.events() |> Enum.filter(&(&1.event_type == :timer_in_combat))

      assert timers |> Enum.flat_map(&List.flatten(&1.actions)) |> Enum.map(& &1.datalong) |> Enum.sort() ==
               [24_818, 24_839, 25_586]

      assert Enum.all?(timers, &(AIEvent.phase_allows?(&1, 0) and not AIEvent.phase_allows?(&1, 1)))

      %{actions: [[failure]]} = find(@eranikus, :evade)
      assert %ScriptStep{command: :end_map_event, datalong: 8736, datalong2: 0} = failure
    end

    test "Eranikus calls Tyrande at 85 percent and is redeemed at 20" do
      %{actions: [tyrande], repeatable?: false} = find(@eranikus, :hp, &(&1.param1 == 85))
      assert Enum.any?(tyrande, &match?(%ScriptStep{command: :summon_creature, datalong: @tyrande}, &1))

      [%ScriptStep{sub_scripts: %{1 => [priestesses]}}] = Enum.filter(tyrande, &(&1.command == :start_script))
      assert %ScriptStep{datalong: 15_634, count: 7, dataint3: -1, dataint2: ride_id} = priestesses
      assert [%ScriptStep{command: :set_faction, datalong: 495}, _ride, attack] = priestesses.sub_scripts[ride_id]
      assert %ScriptStep{command: :attack_start, target_param1: @eranikus, delay_ms: 30_000} = attack

      %{actions: [redemption]} = find(@eranikus, :hp, &(&1.param1 == 20))
      assert [%ScriptStep{command: :set_phase, datalong: 1} | _] = redemption
      assert Enum.any?(redemption, &match?(%ScriptStep{command: :clear_auras}, &1))
      assert Enum.any?(redemption, &match?(%ScriptStep{command: :set_faction, datalong: 35}, &1))
      assert Enum.any?(redemption, &match?(%ScriptStep{command: :combat_stop}, &1))

      [%ScriptStep{sub_scripts: %{1 => scene}}] = Enum.filter(redemption, &(&1.command == :start_script))
      assert Enum.any?(scene, &match?(%ScriptStep{command: :cast_spell, datalong: 25_846}, &1))
    end

    test "the redeemed Eranikus's farewell has Remulos credit the quest and leave" do
      farewell = find(@eranikus, :movement_inform, &(&1.param2 == 12))
      refute AIEvent.phase_allows?(farewell, 0)

      %{actions: [[%ScriptStep{dataint: 11_323}, %ScriptStep{sub_scripts: %{1 => scene}}]]} = farewell

      %ScriptStep{sub_scripts: %{1 => outro}} =
        Enum.find(scene, &match?(%ScriptStep{command: :start_script_for_all, datalong3: @remulos}, &1))

      assert [%ScriptStep{command: :quest_explored, datalong: 8736, target_type: :map_event_target} | _] = outro
      assert Enum.any?(outro, &match?(%ScriptStep{command: :end_map_event, datalong: 8736, datalong2: 1}, &1))
    end

    test "Remulos heals and casts Starfire only during the escort's phase" do
      events = CreatureScript.events(@remulos)

      assert [_heal, _starfire] = events

      assert Enum.all?(
               events,
               &(AIEvent.phase_allows?(&1, Eranikus.nightmare_phase()) and not AIEvent.phase_allows?(&1, 0))
             )
    end

    test "Tyrande rides to the shrine, then channels her absolution" do
      %{actions: [[_arrives, ride]]} = find(@tyrande, :spawned)
      assert %ScriptStep{command: :move_to, dataint: kneel_point} = ride

      %{actions: [arrival]} = find(@tyrande, :movement_inform, &(&1.param2 == kneel_point))
      assert Enum.any?(arrival, &match?(%ScriptStep{command: :remove_aura, datalong: 16_056}, &1))

      %{actions: [[channel, _absolution]]} = find(@tyrande, :movement_inform, &(&1.param2 != kneel_point))
      assert %ScriptStep{command: :cast_spell, datalong: 23_017, target_self?: true} = channel
    end
  end

  defp find(entry, event_type, filter \\ fn _event -> true end) do
    entry |> CreatureScript.events() |> Enum.find(&(&1.event_type == event_type and filter.(&1)))
  end
end
