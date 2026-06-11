defmodule ThistleTea.Game.Aura.Holder do
  @moduledoc """
  All auras applied by one cast of a spell on a unit: source spell and caster,
  display slot, expiry, and the contained `Aura` effects.
  """
  defstruct [
    :spell,
    :caster_guid,
    :caster_level,
    :slot,
    :applied_at,
    :expires_at,
    auras: [],
    negative?: false
  ]
end
