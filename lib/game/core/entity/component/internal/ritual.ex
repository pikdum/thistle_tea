defmodule ThistleTea.Game.Core.Entity.Component.Internal.Ritual do
  @moduledoc """
  Runtime state decoded from a summoning-ritual game-object template, plus its
  owner, selected target, unique participants, and completion state.

  A placed ritual, such as an altar in a dungeon, has no owner. Its first
  participant stands in for one: helpers group with them, and they cast the
  completion spell.
  """

  defstruct [
    :owner_guid,
    :first_user_guid,
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
