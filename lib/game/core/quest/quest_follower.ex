defmodule ThistleTea.Game.Core.Quest.QuestFollower do
  @moduledoc """
  A follower quest that vmangos scripts in C++ (`FollowerAI`), kept as data:
  once a player accepts the quest, the follower trails them until it reaches
  its goal, then credits the player's group and plays its arrival.

  `start_steps/1` lowers one into the generic script commands the creature
  interpreter already runs. Starting it begins a scripted map event keyed by
  the quest, runs the accept actions, clears the npc flags, and follows the
  player at `distance` and `angle`. The event fails the quest and respawns
  the follower if it dies or strays further than `max_distance` from the
  player. It succeeds once the follower reaches its `goal`, either a live
  creature (`{entry, radius}`) or a place (`{:point, {x, y, z}, radius}`):
  the follower stops, credits the player unless `credit?` is false, runs the
  arrival actions, and despawns after `despawn_ms` (never when nil),
  respawning at home later.

  Most followers start when their quest is accepted. One with a `gossip`
  text starts instead from a gossip option of that text, offered while the
  quest is in the player's log and incomplete.

  Accept and arrival actions are written in the `Core.Quest.EscortAction`
  vocabulary.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.EscortAction

  @enforce_keys [:quest_id, :entry, :goal]
  defstruct [
    :quest_id,
    :entry,
    :goal,
    :gossip,
    accept: [],
    arrive: [],
    distance: 2.0,
    angle: :math.pi() / 2,
    credit?: true,
    despawn_ms: 0,
    max_distance: 100
  ]

  @time_limit_s 3_600
  @failure_script 1
  @success_script 3
  @npc_flags_field 147
  @remove_flags 2
  @all_flags 0xFFFF_FFFF
  @source_dead 1
  @idle_motion 0
  @follow_motion 15
  @quest_incomplete 1

  def summon_entries(%__MODULE__{} = follower), do: EscortAction.summon_entries(follower.accept ++ follower.arrive)

  def gossip_condition(%__MODULE__{quest_id: quest_id}),
    do: %Condition{type: :quest_taken, value1: quest_id, value2: @quest_incomplete}

  def start_steps(%__MODULE__{} = follower) do
    [map_event(follower) | Enum.flat_map(follower.accept, &EscortAction.steps(&1, follower.quest_id, :accept))] ++
      [
        %ScriptStep{
          command: :modify_flags,
          datalong: @npc_flags_field,
          datalong2: @all_flags,
          datalong3: @remove_flags
        },
        %ScriptStep{
          command: :movement,
          datalong: @follow_motion,
          position: {follower.distance, 0.0, 0.0, follower.angle}
        }
      ]
  end

  defp map_event(%__MODULE__{quest_id: quest_id} = follower) do
    %ScriptStep{
      command: :start_map_event,
      datalong: quest_id,
      datalong2: @time_limit_s,
      dataint2: @success_script,
      dataint4: @failure_script,
      abort_on_failure?: true,
      failure_condition: %Condition{type: :escort, value1: @source_dead, value2: follower.max_distance},
      success_condition: goal_condition(follower.goal),
      sub_scripts: %{
        @failure_script => [
          %ScriptStep{command: :fail_quest, datalong: quest_id},
          %ScriptStep{command: :respawn_creature, datalong: 1}
        ],
        @success_script => arrival(follower)
      }
    }
  end

  defp goal_condition({:point, {x, y, z}, radius}) do
    %Condition{type: :distance_to_position, value1: x, value2: y, value3: z, value4: radius, swap_targets?: true}
  end

  defp goal_condition({entry, radius}) do
    %Condition{type: :nearby_creature, value1: entry, value2: radius, swap_targets?: true}
  end

  defp arrival(%__MODULE__{quest_id: quest_id} = follower) do
    [%ScriptStep{command: :movement, datalong: @idle_motion}] ++
      credit(follower) ++
      Enum.flat_map(follower.arrive, &EscortAction.steps(&1, quest_id, :arrival)) ++
      despawn(follower.despawn_ms)
  end

  defp credit(%__MODULE__{credit?: false}), do: []

  defp credit(%__MODULE__{quest_id: quest_id, max_distance: max_distance}),
    do: [%ScriptStep{command: :quest_explored, datalong: quest_id, datalong2: max_distance, datalong3: 1}]

  defp despawn(nil), do: []
  defp despawn(despawn_ms), do: [%ScriptStep{command: :despawn, delay_ms: max(despawn_ms, 0)}]
end
