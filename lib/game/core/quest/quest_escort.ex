defmodule ThistleTea.Game.Core.Quest.QuestEscort do
  @moduledoc """
  An escort quest that vmangos scripts in C++ (`npc_escortAI`), kept as data:
  the escortee walks its `script_waypoint` path once a player accepts the
  quest, acting at chosen points, and credits the quest on reaching
  `credit_point`. An escort whose C++ walks its own points instead gives
  them as `path`, a list of `{x, y, z, wait_ms}` numbered from 0. One
  escortee can lead several quests, each with its own entry.

  `start_steps/1` and `point_steps/3` lower one into the generic script
  commands the creature interpreter already runs. Accepting starts a
  scripted map event keyed by the quest that fails the quest and respawns
  the escortee if it dies or strays further than `max_distance` from the
  player, clears the npc flags, and starts the path after `start_delay_ms`.
  Reaching the credit point credits the player. The event stays open until
  the last point's wait runs out, so later points still speak to the player
  and a lost escort still respawns; then the event ends and the escortee
  despawns, respawning at once when `instant_respawn?` is set.

  Accept and point actions are written in the `Core.Quest.EscortAction`
  vocabulary.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.EscortAction

  @enforce_keys [:quest_id, :entry, :credit_point]
  defstruct [
    :quest_id,
    :entry,
    :credit_point,
    accept: [],
    points: %{},
    path: nil,
    max_distance: 100,
    start_delay_ms: 2_500,
    instant_respawn?: false
  ]

  @waypoint_source 4
  @time_limit_s 1_800
  @failure_script 1
  @npc_flags_field 147
  @remove_flags 2
  @all_flags 0xFFFF_FFFF
  @source_dead 1

  def waypoint_source, do: @waypoint_source

  def summon_entries(%__MODULE__{} = escort) do
    EscortAction.summon_entries(escort.accept ++ Enum.flat_map(escort.points, &elem(&1, 1)))
  end

  def start_steps(%__MODULE__{} = escort) do
    [map_event(escort) | Enum.flat_map(escort.accept, &EscortAction.steps(&1, escort.quest_id, :accept))] ++
      [
        %ScriptStep{
          command: :modify_flags,
          datalong: @npc_flags_field,
          datalong2: @all_flags,
          datalong3: @remove_flags
        },
        %ScriptStep{
          command: :start_waypoints,
          datalong: @waypoint_source,
          datalong3: escort.start_delay_ms,
          dataint3: escort.quest_id
        }
      ]
  end

  def point_steps(%__MODULE__{} = escort, last_point, last_wait_ms)
      when is_integer(last_point) and is_integer(last_wait_ms) do
    escort.points
    |> Map.new(fn {point, actions} ->
      {point, Enum.flat_map(actions, &EscortAction.steps(&1, escort.quest_id, :point))}
    end)
    |> append(escort.credit_point, [credit(escort)])
    |> append(last_point, finish(escort, last_wait_ms))
  end

  defp append(points, point, steps), do: Map.update(points, point, steps, &(&1 ++ steps))

  defp map_event(%__MODULE__{quest_id: quest_id} = escort) do
    %ScriptStep{
      command: :start_map_event,
      datalong: quest_id,
      datalong2: @time_limit_s,
      dataint4: @failure_script,
      abort_on_failure?: true,
      failure_condition: %Condition{type: :escort, value1: @source_dead, value2: escort.max_distance},
      sub_scripts: %{
        @failure_script => [
          %ScriptStep{command: :fail_quest, datalong: quest_id},
          %ScriptStep{command: :respawn_creature, datalong: 1}
        ]
      }
    }
  end

  defp credit(%__MODULE__{quest_id: quest_id} = escort) do
    %ScriptStep{
      command: :quest_explored,
      datalong: quest_id,
      datalong2: escort.max_distance,
      datalong3: 1,
      target_type: :map_event_target,
      target_param1: quest_id
    }
  end

  defp finish(%__MODULE__{quest_id: quest_id, instant_respawn?: instant?}, wait_ms) do
    delay_ms = max(wait_ms, 0)

    [
      %ScriptStep{command: :end_map_event, datalong: quest_id, datalong2: 1, delay_ms: delay_ms},
      %ScriptStep{command: :despawn, delay_ms: delay_ms, datalong2: if(instant?, do: 1, else: 0)}
    ]
  end
end
