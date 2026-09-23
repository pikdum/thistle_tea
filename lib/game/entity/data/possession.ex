defmodule ThistleTea.Game.Entity.Data.Possession do
  @moduledoc "The incoming controller and faction to restore when player possession ends."

  @enforce_keys [:caster_guid, :spell_id, :original_faction_template]
  defstruct [:caster_guid, :spell_id, :original_faction_template]
end
