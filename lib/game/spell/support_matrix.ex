defmodule ThistleTea.Game.Spell.SupportMatrix do
  @moduledoc """
  Explicit manifest of the spell-data surface: every effect, aura, and
  implicit-target value a player-reachable spell can carry is either mapped
  by the loader (and handled or knowingly inert) or listed here as deferred
  with a label. The `:dbc_db` coverage test walks every trainable class
  spell and fails when a value falls outside this matrix, so new content
  can never silently no-op.

  Deferred auras that are mapped to atoms but currently inert:
  reflect_spells_school, mod_total_threat (Fade), water_breathing,
  state_immunity replacement gaps, empathy, mechanic_resistance,
  reduce_pushback (cast pushback backlog), track_creatures/track_resources
  client fields, auras_visible, and the language/reputation cosmetics.
  """

  @deferred_effects %{
    19 => :block_passive,
    20 => :defense_passive,
    23 => :spell_defense,
    26 => :dodge_passive,
    37 => :spell_defense_dnd,
    39 => :language,
    44 => :skill_step,
    45 => :honor,
    47 => :tradeskill,
    49 => :detect,
    69 => :distract,
    71 => :pickpocket,
    76 => :summon_object_wild,
    78 => :attack,
    83 => :duel,
    84 => :stuck,
    86 => :holiday_gift,
    94 => :self_resurrect,
    95 => :skinning,
    103 => :reputation,
    116 => :remove_insignia,
    118 => :skill
  }

  @deferred_auras %{
    19 => :mod_invisibility_detect,
    32 => :mod_mounted_speed,
    75 => :mod_language,
    78 => :mounted,
    93 => :death_ward,
    100 => :auras_visible,
    155 => :water_breathing_pct,
    156 => :mod_reputation_gain,
    159 => :honorless_target,
    168 => :mod_damage_done_versus,
    169 => :mod_crit_percent_versus,
    172 => :mod_mounted_speed_not_stack,
    185 => :mod_attacker_ranged_hit_chance,
    186 => :mod_attacker_spell_hit_chance,
    192 => :vmangos_linked_aura
  }

  @deferred_targets %{
    9 => :home_bind,
    17 => :database_location,
    23 => :gameobject,
    25 => :any_unit,
    26 => :locked_object,
    27 => :unit_master,
    35 => :party_member,
    37 => :friend_and_party,
    38 => :script_near_caster,
    40 => :gameobject_script,
    41 => :front_left_totem,
    42 => :back_left_totem,
    43 => :back_right_totem,
    44 => :front_right_totem,
    46 => :script_location,
    47 => :caster_front,
    52 => :gameobjects_at_dest,
    55 => :caster_front_leap,
    63 => :unit_position
  }

  def known_effect?(value) when is_atom(value), do: true
  def known_effect?(value), do: is_map_key(@deferred_effects, value)

  def known_aura?(nil), do: true
  def known_aura?(value) when is_atom(value), do: true
  def known_aura?(value), do: is_map_key(@deferred_auras, value)

  def known_target?(nil), do: true
  def known_target?(value) when is_atom(value), do: true
  def known_target?(value), do: is_map_key(@deferred_targets, value)

  def deferred_effects, do: @deferred_effects
  def deferred_auras, do: @deferred_auras
  def deferred_targets, do: @deferred_targets
end
