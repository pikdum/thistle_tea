defmodule ThistleTea.Game.Aura do
  defstruct [
    :index,
    :type,
    :amount,
    :misc_value,
    :amplitude_ms,
    :next_tick_at,
    :trigger_spell_id
  ]
end
