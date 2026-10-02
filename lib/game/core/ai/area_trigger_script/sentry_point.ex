defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.SentryPoint do
  @moduledoc """
  vmangos `at_sentry_point`: reaching Sentry Point in Dustwallow Marsh
  finishes the fourteenth part of The Missing Diplomat (1265), and Archmage
  Tervosh teleports in from Theramore to hear the report. The guards beside
  him salute, and a minute later he teleports home again. Players at the
  point share the one Tervosh while he is there.

  vmangos scripts only the quest's own trigger, but it overlaps the tower
  entrance trigger, and a client walking in through the door reports only
  the entrance. Both run the script here.

  vmangos makes the visiting Tervosh unattackable and immune to creatures;
  his reward to the player is `CreatureScript.ArchmageTervosh`.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @tower_entrance 302
  @sentry_point 1667
  @missing_diplomat 1265
  @tervosh 4967
  @sentry_point_guard 5085
  @arrival_visual 7141
  @departure_visual 7077
  @salute 66
  @incomplete 1
  @visit_ms 63_000
  @departure_ms 61_000
  @unique_limit 1
  @unique_distance 15
  @unique 0x04
  @no_attack -1
  @timed_despawn 3
  @visit_script 1
  @unit_flags 46
  @not_attackable_and_immune_to_npc 0x280
  @set_flags 1
  @salute_radius 10

  @arrival {-3476.860840, -4106.740723, 17.107151, 5.420159}

  @impl AreaTriggerScript
  def triggers, do: [@tower_entrance, @sentry_point]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @tervosh,
        datalong2: @visit_ms,
        datalong3: @unique_limit,
        datalong4: @unique_distance,
        dataint: @unique,
        dataint2: @visit_script,
        dataint3: @no_attack,
        dataint4: @timed_despawn,
        position: @arrival,
        sub_scripts: %{@visit_script => visit()},
        condition: unfinished()
      },
      %ScriptStep{command: :quest_explored, datalong: @missing_diplomat, condition: unfinished()}
    ]
  end

  defp visit do
    [
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags,
        datalong2: @not_attackable_and_immune_to_npc,
        datalong3: @set_flags
      },
      %ScriptStep{command: :cast_spell, datalong: @arrival_visual, delay_ms: 1_000, target_self?: true},
      %ScriptStep{
        command: :emote,
        datalong: @salute,
        delay_ms: 3_000,
        target_type: :nearest_creature_with_entry,
        target_param1: @sentry_point_guard,
        target_param2: @salute_radius,
        swap_final?: true
      },
      %ScriptStep{command: :cast_spell, datalong: @departure_visual, delay_ms: @departure_ms, target_self?: true}
    ]
  end

  defp unfinished, do: %Condition{type: :quest_taken, value1: @missing_diplomat, value2: @incomplete}
end
