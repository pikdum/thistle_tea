defmodule ThistleTea.Game.Core.Entity.Component.Internal.Creature do
  @moduledoc """
  Creature-template config and scripted overrides carried by mobs: the spawn's db guid (for
  guid-scoped script conditions), the XP reward inputs (multiplier, extra
  flags, elite rank), static combat defaults, the type flags driving visibility rules, the
  regeneration flags, the spell list driving combat casts, the abilities offered to
  whoever controls it, the addon auras applied at spawn, the aggro/assist/leash
  ranges, the civilian's outstanding guard call, and whether a script has
  taken it into the air or set it down (`script_flight`, nil while its
  template decides). A scripted caster chase distance keeps it at casting
  range instead of following the ordinary melee approach.
  """
  defstruct [
    :db_guid,
    :addon_source,
    :spell_list_id,
    :template_unit_flags,
    :default_equipment,
    :scale_override,
    :experience_multiplier,
    :health_multiplier,
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
    :inhabit_type,
    :damage_multiplier,
    :regenerate_stats,
    :detection_range,
    :call_for_help_range,
    :leash_range,
    :script_faction_original,
    :script_faction_value,
    :script_faction_flags,
    :reaction_state,
    :guard_call,
    :script_flight,
    :caster_chase_distance,
    :gossip_menu_id,
    stationary?: false,
    critter?: false,
    civilian?: false,
    racial_leader?: false,
    spells: [],
    charm_spells: [],
    addon_auras: [],
    ai_events: []
  ]
end
