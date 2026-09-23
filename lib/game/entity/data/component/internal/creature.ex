defmodule ThistleTea.Game.Entity.Data.Component.Internal.Creature do
  @moduledoc """
  Static creature-template config carried by mobs: the spawn's db guid (for
  guid-scoped script conditions), the XP reward inputs (multiplier, extra
  flags, elite rank), static combat defaults, the type flags driving visibility rules, the
  regeneration flags, the spell list driving combat casts, the addon auras
  applied at spawn, and the aggro/assist/leash ranges.
  """
  defstruct [
    :db_guid,
    :experience_multiplier,
    :extra_flags,
    :static_flags,
    :static_flags2,
    :mechanic_immune_mask,
    :school_immune_mask,
    :damage_school,
    :rank,
    :family,
    :type_flags,
    :creature_type,
    :damage_multiplier,
    :regenerate_stats,
    :detection_range,
    :call_for_help_range,
    :leash_range,
    :script_faction_original,
    :script_faction_value,
    :script_faction_flags,
    stationary?: false,
    critter?: false,
    civilian?: false,
    racial_leader?: false,
    spells: [],
    addon_auras: [],
    ai_events: []
  ]
end
