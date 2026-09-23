defmodule ThistleTea.Game.Spell.SupportMatrix do
  @moduledoc """
  Explicit manifest of the spell-data surface: every effect, aura, and
  implicit-target value a player-reachable spell can carry is either mapped
  by the loader (and handled or knowingly inert) or listed here as deferred
  with a label. The `:dbc_db` coverage test walks every trainable class
  spell and fails when a value falls outside this matrix, so new content
  can never silently no-op.

  VMangos linked auras remain deferred.
  """

  @deferred_effects %{
    19 => :block_passive,
    20 => :defense_passive,
    26 => :dodge_passive,
    37 => :spell_defense_dnd,
    47 => :tradeskill,
    49 => :detect,
    78 => :attack,
    84 => :stuck,
    86 => :holiday_gift,
    116 => :remove_insignia
  }

  @deferred_auras %{
    192 => :vmangos_linked_aura
  }

  @deferred_targets %{
    17 => :database_location,
    23 => :gameobject,
    26 => :locked_object,
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
