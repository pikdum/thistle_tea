defmodule ThistleTea.Game.Spell.Effect do
  @moduledoc """
  One of a spell's up-to-three effects from the DBC: type, points/dice,
  aura info, targeting, and the damage roll helper.
  """
  defstruct [
    :index,
    :type,
    :base_points,
    :die_sides,
    :real_points_per_level,
    :points_per_combo,
    :aura,
    :amplitude_ms,
    :misc_value,
    :multiple_value,
    :class_mask,
    :item_type,
    :radius_yards,
    :implicit_target_a,
    :implicit_target_b,
    :chain_targets,
    :trigger_spell_id,
    :summon_slot,
    damage_multiplier: 1.0
  ]

  def damage_roll(%__MODULE__{base_points: base, die_sides: sides})
      when is_integer(base) and is_integer(sides) and sides > 0 do
    base + Enum.random(1..sides)
  end

  def damage_roll(%__MODULE__{base_points: base}) when is_integer(base), do: base
  def damage_roll(%__MODULE__{}), do: 0

  def amount(%__MODULE__{} = effect, combo_points) when is_integer(combo_points) and combo_points > 0 do
    damage_roll(effect) + trunc((effect.points_per_combo || 0.0) * combo_points)
  end

  def amount(%__MODULE__{} = effect, _combo_points), do: damage_roll(effect)
end
