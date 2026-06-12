defmodule ThistleTea.Game.Entity.Data.Component.Internal.Summon do
  @moduledoc """
  A summoned game object's lifetime and use config: the owning caster, the
  despawn timer, and the spellcaster spell with its remaining charges.
  """
  defstruct [
    :owner_guid,
    :despawn_in_ms,
    :spell_id,
    :charges,
    party_only?: false
  ]
end
