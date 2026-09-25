defmodule ThistleTea.Game.Aura do
  @moduledoc """
  A single aura effect within an applied spell: its type, magnitude, and
  periodic-tick state. Grouped per spell under `ThistleTea.Game.Aura.Holder`.
  """
  defstruct [
    :index,
    :type,
    :appearance,
    :amount,
    :misc_value,
    :multiple_value,
    :class_mask,
    :item_type,
    :amplitude_ms,
    :next_tick_at,
    :persistent_area,
    :trigger_spell_id
  ]
end
