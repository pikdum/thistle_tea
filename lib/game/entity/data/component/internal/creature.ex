defmodule ThistleTea.Game.Entity.Data.Component.Internal.Creature do
  @moduledoc """
  Static creature-template config carried by mobs: the XP reward inputs
  (multiplier, extra flags, elite rank), the type flags driving visibility
  rules, the regeneration flags, the spell list driving combat casts, the
  addon auras applied at spawn, and the aggro/assist/leash ranges.
  """
  defstruct [
    :experience_multiplier,
    :extra_flags,
    :rank,
    :type_flags,
    :damage_multiplier,
    :regenerate_stats,
    :detection_range,
    :call_for_help_range,
    :leash_range,
    spells: [],
    addon_auras: []
  ]
end
