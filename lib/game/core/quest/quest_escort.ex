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

  Actions are `{:say, text_id}` (spoken to the player),
  `{:say_by, entry, text_id}` (spoken by the nearest creature of that entry),
  `{:emote, emote_id}`, `{:stand, stand_state}`, `{:faction, faction_id}`
  (until respawn), `:run`, `:walk`, `{:add_aura, spell_id}`,
  `{:remove_aura, spell_id}`, `{:remove_unit_flags, mask}` (until
  respawn), `{:summon, entry, position, opts}`, and
  `{:after, delay_ms, action}`. A summon despawns per `despawn:
  {type, delay_ms}` (vmangos `TempSummonType` names), attacks the escortee,
  the player, or nothing per `attack:`, and runs the actions in `script:`.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

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
  @summon_script 2
  @npc_flags_field 147
  @unit_flags_field 46
  @remove_flags 2
  @all_flags 0xFFFF_FFFF
  @restore_on_respawn 1
  @source_dead 1
  @speaker_radius 30
  @attack_none -1
  @attack_self 8
  @attack_event_target 23

  @despawn_types %{
    timed_or_dead: 1,
    timed_or_corpse: 2,
    timed: 3,
    timed_out_of_combat: 4,
    corpse: 5,
    corpse_timed: 6,
    dead: 7
  }

  def waypoint_source, do: @waypoint_source

  def summon_entries(%__MODULE__{} = escort) do
    (escort.accept ++ Enum.flat_map(escort.points, &elem(&1, 1)))
    |> Enum.flat_map(&summon_entry/1)
    |> Enum.uniq()
  end

  defp summon_entry({:after, _delay_ms, action}), do: summon_entry(action)
  defp summon_entry({:summon, entry, _position, _opts}), do: [entry]
  defp summon_entry(_action), do: []

  def start_steps(%__MODULE__{} = escort) do
    [map_event(escort) | Enum.flat_map(escort.accept, &steps(&1, escort, :accept))] ++
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
    |> Map.new(fn {point, actions} -> {point, Enum.flat_map(actions, &steps(&1, escort, :point))} end)
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

  defp steps({:after, delay_ms, action}, escort, phase) when is_integer(delay_ms) do
    action |> steps(escort, phase) |> Enum.map(&%{&1 | delay_ms: &1.delay_ms + delay_ms})
  end

  defp steps({:say, text_id}, escort, phase),
    do: [player_target(%ScriptStep{command: :talk, dataint: text_id}, escort, phase)]

  defp steps({:say_by, entry, text_id}, _escort, _phase) do
    [
      %ScriptStep{
        command: :talk,
        dataint: text_id,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @speaker_radius,
        swap_final?: true
      }
    ]
  end

  defp steps({:emote, emote_id}, _escort, _phase), do: [%ScriptStep{command: :emote, datalong: emote_id}]
  defp steps({:stand, stand_state}, _escort, _phase), do: [%ScriptStep{command: :stand_state, datalong: stand_state}]

  defp steps({:faction, faction_id}, _escort, _phase) do
    [%ScriptStep{command: :set_faction, datalong: faction_id, datalong2: @restore_on_respawn}]
  end

  defp steps(:run, _escort, _phase), do: [%ScriptStep{command: :set_run, datalong: 1}]
  defp steps(:walk, _escort, _phase), do: [%ScriptStep{command: :set_run, datalong: 0}]
  defp steps({:add_aura, spell_id}, _escort, _phase), do: [%ScriptStep{command: :add_aura, datalong: spell_id}]
  defp steps({:remove_aura, spell_id}, _escort, _phase), do: [%ScriptStep{command: :remove_aura, datalong: spell_id}]

  defp steps({:remove_unit_flags, mask}, _escort, _phase) do
    [%ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: @remove_flags}]
  end

  defp steps({:summon, entry, {_x, _y, _z, _o} = position, opts}, %__MODULE__{} = escort, phase) do
    {despawn_type, despawn_ms} = Keyword.get(opts, :despawn, {:timed_or_dead, 25_000})
    script = Enum.flat_map(Keyword.get(opts, :script, []), &steps(&1, escort, :summon))

    [
      %ScriptStep{
        command: :summon_creature,
        datalong: entry,
        datalong2: despawn_ms,
        dataint2: if(script == [], do: 0, else: @summon_script),
        dataint3: attack_type(Keyword.get(opts, :attack), phase),
        dataint4: Map.fetch!(@despawn_types, despawn_type),
        target_param1: escort.quest_id,
        position: position,
        sub_scripts: if(script == [], do: %{}, else: %{@summon_script => script})
      }
    ]
  end

  defp attack_type(nil, _phase), do: @attack_none
  defp attack_type(:escort, _phase), do: @attack_self
  defp attack_type(:player, :accept), do: 0
  defp attack_type(:player, _phase), do: @attack_event_target

  defp player_target(step, %__MODULE__{quest_id: quest_id}, :point),
    do: %{step | target_type: :map_event_target, target_param1: quest_id}

  defp player_target(step, %__MODULE__{}, _phase), do: step
end
