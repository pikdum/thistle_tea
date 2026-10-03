defmodule ThistleTea.Game.Core.AI.CreatureScript.WitchDoctorUnbagwa do
  @moduledoc """
  vmangos `npc_witch_doctor_unbagwa`, the second Stranglethorn Fever (349)
  in Stranglethorn Vale.

  Turning in the gorilla fangs sets Unbagwa's ritual going: he stops giving
  quests and stands passive while three waves of apes come at him, ten
  seconds apart once each is cleared. Three Enraged Silverbacks lead off,
  Konda follows four more, and Mokk the Savage, whose heart the first
  Stranglethorn Fever wants, follows five. One map event per wave counts its
  dead apes; clearing the last wave, or leaving a wave alive past the three
  minutes its apes last, puts Unbagwa back to giving quests.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @unbagwa 1_449
  @quest 349
  @silverback 1_511
  @konda 1_516
  @mokk 1_514

  @waves [{34_901, 3, nil}, {34_902, 4, @konda}, {34_903, 5, @mokk}]
  @apes_spawn {-13_773.6231, -3.8856, 41.5641, 5.7}

  @escort_passive 113
  @restore_default_faction 0
  @npc_flags 147
  @questgiver 0x2
  @add_flags 1
  @remove_flags 2
  @ape_lifetime_ms 180_000
  @wave_limit_s 180
  @wave_delay_ms 10_000
  @timed_or_dead_despawn 1
  @attack_summoner 8
  @apes_scatter 3.0
  @source_dead 1
  @dead 0
  @at_least 1
  @success_script 1
  @failure_script 2

  @impl CreatureScript
  def entries, do: [@unbagwa]

  @impl CreatureScript
  def events(@unbagwa) do
    [@silverback, @konda, @mokk]
    |> Enum.with_index(1)
    |> Enum.map(fn {ape, index} ->
      CreatureScript.event(@unbagwa, index, :summoned_just_died, Enum.map(@waves, &count_dead/1), param1: ape)
    end)
  end

  @impl CreatureScript
  def quest_end_steps do
    %{
      @quest => [
        %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @questgiver, datalong3: @remove_flags},
        CreatureScript.faction(@escort_passive)
        | wave(@waves)
      ]
    }
  end

  defp wave([{event_id, silverbacks, leader} = current | later]) do
    [
      %ScriptStep{
        command: :start_map_event,
        datalong: event_id,
        datalong2: @wave_limit_s,
        dataint2: @success_script,
        dataint4: @failure_script,
        success_condition: cleared(current),
        failure_condition: %Condition{type: :escort, value1: @source_dead},
        sub_scripts: %{
          @success_script => if(later == [], do: restore(), else: wave(later)),
          @failure_script => restore_while_alive()
        }
      },
      CreatureScript.timed([%{apes(@silverback, silverbacks) | delay_ms: @wave_delay_ms} | leader(leader)])
    ]
  end

  defp leader(nil), do: []
  defp leader(entry), do: [%{apes(entry, 1) | delay_ms: @wave_delay_ms}]

  defp apes(entry, count) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @ape_lifetime_ms,
      dataint3: @attack_summoner,
      dataint4: @timed_or_dead_despawn,
      position: @apes_spawn,
      scatter: @apes_scatter,
      count: count
    }
  end

  defp restore_while_alive, do: Enum.map(restore(), &%{&1 | condition: %Condition{type: :alive, swap_targets?: true}})

  defp restore do
    [
      %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @questgiver, datalong3: @add_flags},
      %ScriptStep{command: :set_faction, datalong: @restore_default_faction}
    ]
  end

  defp count_dead({event_id, _silverbacks, _leader}) do
    %ScriptStep{command: :set_map_event_data, datalong: event_id, datalong2: @dead, datalong3: 1, datalong4: 1}
  end

  defp cleared({event_id, silverbacks, leader}) do
    apes = silverbacks + if(leader, do: 1, else: 0)
    %Condition{type: :map_event_data, value1: event_id, value2: @dead, value3: apes, value4: @at_least}
  end
end
