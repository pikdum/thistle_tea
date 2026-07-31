defmodule ThistleTea.Game.Entity.Data.ScriptStep do
  @moduledoc """
  One step of a generic vmangos script (`creature_ai_scripts`,
  `creature_movement_scripts`, and the other `*_scripts` tables share the
  format): a command with its raw params, decoded target selector and general
  flags, and — for talk steps — the broadcast texts resolved at load time.
  Unsupported commands keep their numeric id as `{:unsupported, id}` so the
  interpreter can log and skip them.
  """
  import Bitwise, only: [&&&: 2]

  defstruct script_id: 0,
            delay_ms: 0,
            priority: 0,
            command: {:unsupported, 0},
            datalong: 0,
            datalong2: 0,
            datalong3: 0,
            datalong4: 0,
            dataint: 0,
            dataint2: 0,
            dataint3: 0,
            dataint4: 0,
            target_type: :provided,
            target_param1: 0,
            target_param2: 0,
            target_self?: false,
            swap_initial?: false,
            swap_final?: false,
            buddy_guid: nil,
            game_object_spawn: nil,
            equipment_items: [],
            position: nil,
            condition_id: 0,
            condition: nil,
            success_condition: nil,
            failure_condition: nil,
            target_condition: nil,
            termination_condition: nil,
            texts: [],
            sub_scripts: %{}

  @flag_swap_initial_targets 0x01
  @flag_swap_final_targets 0x02
  @flag_target_self 0x04

  def build(row) when is_map(row) do
    %__MODULE__{
      script_id: row.id,
      delay_ms: int(row.delay) * 1_000,
      priority: int(row.priority),
      command: command(row.command),
      datalong: int(row.datalong),
      datalong2: int(row.datalong2),
      datalong3: int(row.datalong3),
      datalong4: int(row.datalong4),
      dataint: int(row.dataint),
      dataint2: int(row.dataint2),
      dataint3: int(row.dataint3),
      dataint4: int(row.dataint4),
      target_type: target_type(row.target_type),
      target_param1: int(row.target_param1),
      target_param2: int(row.target_param2),
      target_self?: flag?(row.data_flags, @flag_target_self),
      swap_initial?: flag?(row.data_flags, @flag_swap_initial_targets),
      swap_final?: flag?(row.data_flags, @flag_swap_final_targets),
      position: {num(row.x), num(row.y), num(row.z), num(row.o)},
      condition_id: int(row.condition_id)
    }
  end

  defp int(value) when is_integer(value), do: value
  defp int(_value), do: 0

  defp num(value) when is_number(value), do: value
  defp num(_value), do: 0.0

  def talk_text_ids(%__MODULE__{command: :talk} = step) do
    Enum.filter([step.dataint, step.dataint2, step.dataint3, step.dataint4], &(is_integer(&1) and &1 > 0))
  end

  def talk_text_ids(%__MODULE__{}), do: []

  def emote_ids(%__MODULE__{command: :emote} = step) do
    Enum.filter([step.datalong, step.datalong2, step.datalong3, step.datalong4], &(is_integer(&1) and &1 > 0))
  end

  def emote_ids(%__MODULE__{}), do: []

  def cast_spell_id(%__MODULE__{command: :cast_spell, datalong: spell_id}) when is_integer(spell_id) and spell_id > 0 do
    spell_id
  end

  def cast_spell_id(%__MODULE__{}), do: nil

  defp flag?(flags, bit) when is_integer(flags), do: (flags &&& bit) != 0
  defp flag?(_flags, _bit), do: false

  def nested_script_ids(%__MODULE__{command: :summon_creature, dataint2: script_id}) when script_id > 0 do
    [script_id]
  end

  def nested_script_ids(%__MODULE__{command: :start_script} = step) do
    Enum.filter([step.datalong, step.datalong2, step.datalong3, step.datalong4], &(is_integer(&1) and &1 > 0))
  end

  def nested_script_ids(%__MODULE__{command: command} = step)
      when command in [:start_map_event, :add_map_event_target, :edit_map_event] do
    Enum.filter([step.dataint2, step.dataint4], &(is_integer(&1) and &1 > 0))
  end

  def nested_script_ids(%__MODULE__{command: :start_script_for_all, datalong: script_id})
      when is_integer(script_id) and script_id > 0, do: [script_id]

  def nested_script_ids(%__MODULE__{}), do: []

  def condition_ids(%__MODULE__{} = step) do
    event_condition_ids =
      case step.command do
        command when command in [:start_map_event, :add_map_event_target, :edit_map_event] ->
          [step.dataint, step.dataint3]

        :remove_map_event_target ->
          [step.datalong2]

        :terminate_condition ->
          [step.datalong]

        _command ->
          []
      end

    Enum.filter([step.condition_id | event_condition_ids], &(is_integer(&1) and &1 > 0))
  end

  def start_script_options(%__MODULE__{command: :start_script} = step) do
    [
      {step.datalong, step.dataint},
      {step.datalong2, step.dataint2},
      {step.datalong3, step.dataint3},
      {step.datalong4, step.dataint4}
    ]
    |> Enum.filter(fn {script_id, _chance} -> is_integer(script_id) and script_id > 0 end)
  end

  def start_script_options(%__MODULE__{}), do: []

  @summon_flag_set_run 0x01
  @summon_flag_unique 0x04
  @summon_flag_unique_temp 0x08

  def summon(%__MODULE__{command: :summon_creature} = step) do
    %{
      entry: step.datalong,
      despawn_delay_ms: step.datalong2,
      unique_limit: step.datalong3,
      unique_distance: step.datalong4,
      run?: flag?(step.dataint, @summon_flag_set_run),
      unique?: flag?(step.dataint, @summon_flag_unique) or flag?(step.dataint, @summon_flag_unique_temp),
      script_id: step.dataint2,
      attack_target: decode_target_type(step.dataint3),
      despawn_type: step.dataint4,
      position: step.position
    }
  end

  defp command(0), do: :talk
  defp command(1), do: :emote
  defp command(3), do: :move_to
  defp command(4), do: :modify_flags
  defp command(5), do: :interrupt_casts
  defp command(7), do: :quest_explored
  defp command(8), do: :kill_credit
  defp command(9), do: :respawn_game_object
  defp command(10), do: :summon_creature
  defp command(13), do: :activate_object
  defp command(14), do: :remove_aura
  defp command(15), do: :cast_spell
  defp command(16), do: :play_sound
  defp command(17), do: :create_item
  defp command(18), do: :despawn
  defp command(19), do: :set_equipment
  defp command(20), do: :movement
  defp command(22), do: :set_faction
  defp command(23), do: :morph
  defp command(24), do: :mount
  defp command(25), do: :set_run
  defp command(26), do: :attack_start
  defp command(28), do: :stand_state
  defp command(30), do: :send_taxi_path
  defp command(31), do: :terminate_script
  defp command(32), do: :terminate_condition
  defp command(34), do: :set_home_position
  defp command(35), do: :turn_to
  defp command(39), do: :start_script
  defp command(41), do: :remove_object
  defp command(44), do: :set_phase
  defp command(45), do: :set_phase_random
  defp command(46), do: :set_phase_range
  defp command(47), do: :flee
  defp command(51), do: :set_sheath
  defp command(60), do: :start_waypoints
  defp command(61), do: :start_map_event
  defp command(62), do: :end_map_event
  defp command(63), do: :add_map_event_target
  defp command(64), do: :remove_map_event_target
  defp command(65), do: :set_map_event_data
  defp command(66), do: :send_map_event
  defp command(67), do: :set_default_movement
  defp command(68), do: :start_script_for_all
  defp command(69), do: :edit_map_event
  defp command(70), do: :fail_quest
  defp command(71), do: :respawn_creature
  defp command(73), do: :combat_stop
  defp command(74), do: :add_aura
  defp command(76), do: :summon_object
  defp command(80), do: :set_game_object_state
  defp command(81), do: :despawn_game_object
  defp command(82), do: :load_game_object_spawn
  defp command(83), do: :quest_credit
  defp command(89), do: :play_custom_animation
  defp command(other), do: {:unsupported, other}

  def decode_target_type(value) when is_integer(value) and value < 0, do: nil
  def decode_target_type(value), do: target_type(value)

  defp target_type(0), do: :provided
  defp target_type(1), do: :victim
  defp target_type(2), do: :hostile_second_aggro
  defp target_type(3), do: :hostile_last_aggro
  defp target_type(4), do: :hostile_random
  defp target_type(5), do: :hostile_random_not_top
  defp target_type(8), do: :owner_or_self
  defp target_type(10), do: :nearest_creature_with_entry
  defp target_type(11), do: :creature_with_guid
  defp target_type(13), do: :nearest_game_object_with_entry
  defp target_type(14), do: :game_object_with_guid
  defp target_type(16), do: :friendly
  defp target_type(17), do: :friendly_injured
  defp target_type(18), do: :friendly_injured_except
  defp target_type(19), do: :friendly_missing_buff
  defp target_type(20), do: :friendly_missing_buff_except
  defp target_type(28), do: :random_creature_with_entry
  defp target_type(other), do: {:unsupported, other}
end
