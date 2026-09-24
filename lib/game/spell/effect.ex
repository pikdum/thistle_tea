defmodule ThistleTea.Game.Spell.Effect do
  @moduledoc """
  One of a spell's up-to-three effects from the DBC (with VMangos
  `spell_effect_mod` overrides applied): type, points/dice, aura info,
  targeting, bonus coefficient, and the value-roll helpers.
  """
  alias ThistleTea.Game.Math

  @periodic_auras [
    :periodic_power_burn,
    :periodic_damage_percent,
    :periodic_damage,
    :periodic_heal,
    :periodic_energize,
    :periodic_leech,
    :periodic_health_funnel,
    :periodic_mana_leech,
    :periodic_trigger_spell,
    :obs_mod_health,
    :obs_mod_mana
  ]

  defstruct [
    :index,
    :type,
    :semantic,
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
    mechanic: 0,
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

  def periodic?(%__MODULE__{aura: aura}), do: aura in @periodic_auras

  def period_ms(%__MODULE__{amplitude_ms: period}) when is_integer(period) and period > 0, do: period
  def period_ms(%__MODULE__{aura: :mod_power_regen_percent}), do: 2_000
  def period_ms(%__MODULE__{aura: :obs_mod_mana}), do: 1_000
  def period_ms(%__MODULE__{aura: aura}) when aura in [:mod_regen, :mod_power_regen], do: 5_000
  def period_ms(%__MODULE__{amplitude_ms: period}), do: period

  def amount(%__MODULE__{} = effect, level_units, combo_points) when is_integer(combo_points) and combo_points > 0 do
    roll(effect, level_units) + trunc((effect.points_per_combo || 0.0) * combo_points)
  end

  def amount(%__MODULE__{} = effect, level_units, _combo_points), do: roll(effect, level_units)

  def amount(%__MODULE__{} = effect, combo_points), do: amount(effect, 0, combo_points)
end
