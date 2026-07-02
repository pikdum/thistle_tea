defmodule ThistleTea.Game.Entity.Data.Component.Internal.Creature do
  @moduledoc """
  Static creature-template config carried by mobs: the XP reward inputs
  (multiplier, extra flags, elite rank), the type flags driving visibility
  rules, the regeneration flags, and the spell list driving combat casts.
  """
  defstruct [
    :experience_multiplier,
    :extra_flags,
    :rank,
    :type_flags,
    :damage_multiplier,
    :regenerate_stats,
    spells: []
  ]
end
