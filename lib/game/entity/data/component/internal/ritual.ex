defmodule ThistleTea.Game.Entity.Data.Component.Internal.Ritual do
  @moduledoc """
  Runtime state decoded from a summoning-ritual game-object template, plus its
  owner, selected target, unique participants, and completion state.
  """

  defstruct [
    :owner_guid,
    :target_guid,
    :required_participants,
    :completion_spell_id,
    :animation_spell_id,
    :caster_target_spell_id,
    :caster_target_spell_targets,
    :zone_id,
    persistent?: false,
    casters_grouped?: false,
    no_target_check?: false,
    users: MapSet.new(),
    completed?: false
  ]
end
