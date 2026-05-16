defmodule ThistleTea.Game.Aura.Holder do
  defstruct [
    :spell,
    :caster_guid,
    :caster_level,
    :slot,
    :applied_at,
    :expires_at,
    auras: []
  ]
end
