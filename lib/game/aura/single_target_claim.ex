defmodule ThistleTea.Game.Aura.SingleTargetClaim do
  @moduledoc "Identifies one accepted application of a caster-limited aura on its recipient."

  defstruct [
    :caster_guid,
    :target_guid,
    :holder_key,
    :generation,
    :spell_family,
    :spell_icon,
    :category,
    stalked?: false
  ]
end
