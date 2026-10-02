defmodule ThistleTea.Game.Core.AI.CreatureScript.Triage do
  @moduledoc """
  vmangos `npc_doctor` and `npc_injured_patient`, the "Triage" first aid
  quests (6622 for the Horde, 6624 for the Alliance) that open Artisan First
  Aid.

  Accepting the quest starts a map event keyed by the quest and wakes the
  doctor, who lays a random patient in a free bunk every ten seconds. A
  patient arrives at a quarter, half, or three quarters of its health, by how
  badly it is injured, and bleeds 50 health a second without regenerating. A
  Triage Bandage (20804) saves it: the patient stands, thanks the doctor, and
  runs off. Fifteen saves, or the doctor running out of patients after 21,
  complete the quest; a sixth death or the player straying out of sight fails
  it. Either way the remaining patients despawn and the doctor waits for the
  next player.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @horde_doctor 12_920
  @alliance_doctor 12_939
  @horde_quest 6_622
  @alliance_quest 6_624
  @triage 20_804

  @patients %{
    12_923 => {@horde_quest, 75},
    12_924 => {@horde_quest, 50},
    12_925 => {@horde_quest, 25},
    12_938 => {@alliance_quest, 75},
    12_936 => {@alliance_quest, 50},
    12_937 => {@alliance_quest, 25}
  }

  @doctors %{
    @horde_doctor => %{
      quest: @horde_quest,
      patients: [12_923, 12_924, 12_925],
      bunks: [
        {-1013.75, -3492.59, 62.62, 4.34},
        {-1017.72, -3490.92, 62.62, 4.34},
        {-1015.77, -3497.15, 62.82, 4.34},
        {-1019.51, -3495.49, 62.82, 4.34},
        {-1017.25, -3500.85, 62.98, 4.34},
        {-1020.95, -3499.21, 62.98, 4.34}
      ]
    },
    @alliance_doctor => %{
      quest: @alliance_quest,
      patients: [12_938, 12_936, 12_937],
      bunks: [
        {-3757.38, -4533.05, 14.16, 3.62},
        {-3754.36, -4539.13, 14.16, 5.13},
        {-3749.54, -4540.25, 14.28, 3.34},
        {-3742.10, -4536.85, 14.28, 3.64},
        {-3755.89, -4529.07, 14.05, 0.57},
        {-3749.51, -4527.08, 14.07, 5.26},
        {-3746.37, -4525.35, 14.16, 5.22}
      ]
    }
  }

  @exits %{
    @horde_quest => {-1016.44, -3508.48, 62.96, 0.0},
    @alliance_quest => {-3742.96, -4531.52, 11.91, 0.0}
  }

  @saved 0
  @died 1
  @summoned 2
  @saves_needed 15
  @deaths_allowed 5
  @patient_limit 21
  @time_limit_s 300
  @sight_distance 100
  @summon_interval_ms 10_000
  @bleed_interval_ms 1_000
  @bleed_per_second 50
  @saved_despawn_ms 5_000
  @success_script 1
  @failure_script 2
  @despawn_script 3
  @unit_fields_flags 46
  @not_selectable 0x02000000
  @set_flags 1
  @stand 0
  @lie_dead 7
  @no_regeneration 0
  @full_regeneration 3
  @no_attack -1
  @manual_despawn 8
  @thanks [8_355, 8_359, 8_361]

  @impl CreatureScript
  def entries, do: Map.keys(@doctors) ++ Map.keys(@patients)

  @impl CreatureScript
  def events(entry) when is_map_key(@doctors, entry), do: doctor_events(entry, Map.fetch!(@doctors, entry))
  def events(entry) when is_map_key(@patients, entry), do: patient_events(entry, Map.fetch!(@patients, entry))

  @impl CreatureScript
  def quest_start_steps do
    Map.new(@doctors, fn {_doctor, %{quest: quest}} -> {quest, start_steps(quest)} end)
  end

  defp start_steps(quest) do
    [
      %ScriptStep{
        command: :start_map_event,
        datalong: quest,
        datalong2: @time_limit_s,
        dataint2: @success_script,
        dataint4: @failure_script,
        abort_on_failure?: true,
        success_condition:
          any([event_data(quest, @saved, @saves_needed), event_data(quest, @summoned, @patient_limit)]),
        failure_condition:
          any([
            event_data(quest, @died, @deaths_allowed + 1),
            %Condition{type: :escort, value2: @sight_distance}
          ]),
        sub_scripts: %{
          @success_script => [
            %ScriptStep{command: :quest_explored, datalong: quest, datalong2: @sight_distance, datalong3: 1},
            %ScriptStep{command: :set_phase, datalong: 0}
          ],
          @failure_script => [
            %ScriptStep{command: :fail_quest, datalong: quest},
            %ScriptStep{command: :set_phase, datalong: 0}
          ]
        }
      },
      %ScriptStep{command: :set_phase, datalong: 1}
    ]
  end

  defp doctor_events(entry, %{patients: patients, bunks: bunks}) do
    [
      CreatureScript.event(entry, 1, :timer_ooc, [summon_patient(patients, bunks)],
        param1: @summon_interval_ms,
        param2: @summon_interval_ms,
        param3: @summon_interval_ms,
        param4: @summon_interval_ms,
        inverse_phase_mask: CreatureScript.only_in_phases([1])
      )
    ]
  end

  defp summon_patient([first, second, third], bunks) do
    %ScriptStep{
      command: :start_script,
      datalong: first,
      dataint: 34,
      datalong2: second,
      dataint2: 33,
      datalong3: third,
      dataint3: 33,
      sub_scripts: Map.new([first, second, third], &{&1, [summon(&1, bunks)]})
    }
  end

  defp summon(entry, bunks) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      dataint3: @no_attack,
      dataint4: @manual_despawn,
      positions: bunks
    }
  end

  defp patient_events(entry, {quest, health_pct}) do
    dying = CreatureScript.only_in_phases([0])

    [
      CreatureScript.event(entry, 1, :spawned, lie_down(quest, health_pct)),
      CreatureScript.event(entry, 2, :timer_ooc, [%ScriptStep{command: :lose_health, datalong: @bleed_per_second}],
        param1: @bleed_interval_ms,
        param2: @bleed_interval_ms,
        param3: @bleed_interval_ms,
        param4: @bleed_interval_ms,
        inverse_phase_mask: dying
      ),
      CreatureScript.event(entry, 3, :death, [count(quest, @died), %ScriptStep{command: :despawn}]),
      CreatureScript.event(entry, 4, :hit_by_spell, saved(quest), param1: @triage, inverse_phase_mask: dying)
    ]
  end

  defp lie_down(quest, health_pct) do
    [
      %ScriptStep{command: :set_health_pct, datalong: health_pct},
      %ScriptStep{command: :set_regeneration, datalong: @no_regeneration},
      %ScriptStep{command: :stand_state, datalong: @lie_dead},
      %ScriptStep{
        command: :add_map_event_target,
        datalong: quest,
        dataint2: @despawn_script,
        dataint4: @despawn_script,
        sub_scripts: %{@despawn_script => [%ScriptStep{command: :despawn}]}
      },
      count(quest, @summoned)
    ]
  end

  defp saved(quest) do
    [
      %{count(quest, @saved) | condition: %Condition{type: :quest_taken, value1: quest, value2: 1}},
      %ScriptStep{command: :set_phase, datalong: 1},
      %ScriptStep{command: :set_regeneration, datalong: @full_regeneration},
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_fields_flags,
        datalong2: @not_selectable,
        datalong3: @set_flags
      },
      %ScriptStep{command: :stand_state, datalong: @stand},
      talk(@thanks),
      %ScriptStep{command: :set_run, datalong: 1},
      %ScriptStep{command: :move_to, position: Map.fetch!(@exits, quest)},
      %ScriptStep{command: :despawn, datalong: @saved_despawn_ms}
    ]
  end

  defp talk([first, second, third]), do: %ScriptStep{command: :talk, dataint: first, dataint2: second, dataint3: third}

  defp count(quest, index) do
    %ScriptStep{command: :set_map_event_data, datalong: quest, datalong2: index, datalong3: 1, datalong4: 1}
  end

  defp event_data(quest, index, at_least) do
    %Condition{type: :map_event_data, value1: quest, value2: index, value3: at_least, value4: 1}
  end

  defp any(children), do: %Condition{type: :or, children: children}
end
