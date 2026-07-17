defmodule ThistleTea.Game.Aura do
  @moduledoc """
  A single aura effect within an applied spell: its type, magnitude, and
  periodic-tick state. Grouped per spell under `ThistleTea.Game.Aura.Holder`.
  """
  defstruct [
    :index,
    :type,
    :amount,
    :misc_value,
    :multiple_value,
    :class_mask,
    :amplitude_ms,
    :next_tick_at,
    :trigger_spell_id
  ]
end
