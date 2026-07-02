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
            swap_targets?: false,
            position: nil,
            condition_id: 0,
            texts: []

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
      swap_targets?:
        flag?(row.data_flags, @flag_swap_initial_targets) or flag?(row.data_flags, @flag_swap_final_targets),
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

  defp command(0), do: :talk
  defp command(1), do: :emote
  defp command(3), do: :move_to
  defp command(14), do: :remove_aura
  defp command(15), do: :cast_spell
  defp command(44), do: :set_phase
  defp command(45), do: :set_phase_random
  defp command(46), do: :set_phase_range
  defp command(47), do: :flee
  defp command(other), do: {:unsupported, other}

  defp target_type(0), do: :provided
  defp target_type(1), do: :victim
  defp target_type(2), do: :hostile_second_aggro
  defp target_type(3), do: :hostile_last_aggro
  defp target_type(4), do: :hostile_random
  defp target_type(5), do: :hostile_random_not_top
  defp target_type(8), do: :self
  defp target_type(16), do: :friendly
  defp target_type(17), do: :friendly_injured
  defp target_type(18), do: :friendly_injured_except
  defp target_type(19), do: :friendly_missing_buff
  defp target_type(20), do: :friendly_missing_buff_except
  defp target_type(other), do: {:unsupported, other}
end
