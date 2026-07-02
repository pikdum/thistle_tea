defmodule ThistleTea.Game.Entity.Data.AIEvent do
  @moduledoc """
  One EventAI trigger for a creature (vmangos `creature_ai_events` semantics):
  when a data-driven condition fires — a timer, an HP threshold, aggro, death,
  and so on — its action scripts run through the script-command interpreter.
  Params keep the per-type meanings documented in vmangos `CreatureEventAI.h`;
  actions are the referenced script steps resolved at load time. Unsupported
  event types keep their numeric id as `{:unsupported, id}`.
  """
  import Bitwise, only: [&&&: 2]

  defstruct id: 0,
            event_type: {:unsupported, 0},
            chance: 100,
            repeatable?: false,
            random_action?: false,
            not_casting?: false,
            inverse_phase_mask: 0,
            condition_id: 0,
            param1: 0,
            param2: 0,
            param3: 0,
            param4: 0,
            actions: []

  @flag_repeatable 0x01
  @flag_random_action 0x02
  @flag_not_casting 0x04

  def build(row, scripts_by_id) when is_map(row) and is_map(scripts_by_id) do
    actions =
      [row.action1_script, row.action2_script, row.action3_script]
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.map(&Map.get(scripts_by_id, &1, []))
      |> Enum.reject(&(&1 == []))

    %__MODULE__{
      id: row.id,
      event_type: event_type(row.event_type),
      chance: int(row.event_chance, 100),
      repeatable?: flag?(row.event_flags, @flag_repeatable),
      random_action?: flag?(row.event_flags, @flag_random_action),
      not_casting?: flag?(row.event_flags, @flag_not_casting),
      inverse_phase_mask: int(row.event_inverse_phase_mask, 0),
      condition_id: int(row.condition_id, 0),
      param1: int(row.event_param1, 0),
      param2: int(row.event_param2, 0),
      param3: int(row.event_param3, 0),
      param4: int(row.event_param4, 0),
      actions: actions
    }
  end

  defp int(value, _default) when is_integer(value), do: value
  defp int(_value, default), do: default

  def timed?(%__MODULE__{event_type: event_type}) do
    event_type in [:timer_in_combat, :timer_ooc, :hp, :mana, :target_hp, :range, :friendly_hp]
  end

  def phase_allows?(%__MODULE__{inverse_phase_mask: mask}, phase) when is_integer(mask) and is_integer(phase) do
    (mask &&& Bitwise.bsl(1, phase)) == 0
  end

  defp flag?(flags, bit) when is_integer(flags), do: (flags &&& bit) != 0
  defp flag?(_flags, _bit), do: false

  defp event_type(0), do: :timer_in_combat
  defp event_type(1), do: :timer_ooc
  defp event_type(2), do: :hp
  defp event_type(3), do: :mana
  defp event_type(4), do: :aggro
  defp event_type(5), do: :kill
  defp event_type(6), do: :death
  defp event_type(7), do: :evade
  defp event_type(8), do: :hit_by_spell
  defp event_type(9), do: :range
  defp event_type(11), do: :spawned
  defp event_type(12), do: :target_hp
  defp event_type(14), do: :friendly_hp
  defp event_type(30), do: :leave_combat
  defp event_type(other), do: {:unsupported, other}
end
