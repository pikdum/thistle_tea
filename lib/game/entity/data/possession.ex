defmodule ThistleTea.Game.Entity.Data.Possession do
  @moduledoc "Incoming player control, its command state, and the native faction to restore on release."

  @enforce_keys [:caster_guid, :spell_id, :original_faction_template]
  defstruct [
    :caster_guid,
    :spell_id,
    :original_faction_template,
    :original_control_flags,
    :applied_at,
    :command_target,
    kind: :possession,
    command: :follow,
    reaction: :defensive,
    spells: []
  ]
end
