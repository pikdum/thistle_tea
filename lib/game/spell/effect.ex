defmodule ThistleTea.Game.Spell.Effect do
  @moduledoc """
  One of a spell's up-to-three effects from the DBC (with VMangos
  `spell_effect_mod` overrides applied): type, points/dice, aura info,
  targeting, bonus coefficient, and the value-roll helpers.
  """
  alias ThistleTea.Game.Math

  defstruct [
    :index,
    :type,
    :base_points,
    :die_sides,
    :base_dice,
    :dice_per_level,
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
    :bonus_coefficient,
    area_target?: false,
    damage_multiplier: 1.0
  ]

  def roll(%__MODULE__{} = effect, level_units) when is_integer(level_units) do
    base_dice = effect.base_dice || 0
    value = (effect.base_points || 0) + trunc(level_units * (effect.real_points_per_level || 0.0))
    random_points = (effect.die_sides || 0) + trunc(level_units * (effect.dice_per_level || 0.0))

    case random_points do
      points when points in [0, 1] -> value + base_dice
      points -> value + Math.random_int(min(base_dice, points), max(base_dice, points))
    end
  end

  def damage_roll(%__MODULE__{} = effect), do: roll(effect, 0)

  def amount(%__MODULE__{} = effect, level_units, combo_points) when is_integer(combo_points) and combo_points > 0 do
    roll(effect, level_units) + trunc((effect.points_per_combo || 0.0) * combo_points)
  end

  def amount(%__MODULE__{} = effect, level_units, _combo_points), do: roll(effect, level_units)

  def amount(%__MODULE__{} = effect, combo_points), do: amount(effect, 0, combo_points)
end
