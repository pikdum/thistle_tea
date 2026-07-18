defmodule ThistleTea.DB.Mangos.SpellEffectMod do
  @moduledoc """
  VMangos per-effect spell fixes: each column overrides the matching DBC
  effect field when not -1 (explicit 0 is a real override).
  """
  use Ecto.Schema

  @primary_key false
  schema "spell_effect_mod" do
    field(:id, :integer, source: :Id, primary_key: true)
    field(:effect_index, :integer, source: :EffectIndex, primary_key: true)
    field(:effect, :integer, source: :Effect)
    field(:effect_apply_aura_name, :integer, source: :EffectApplyAuraName)
    field(:effect_mechanic, :integer, source: :EffectMechanic)
    field(:effect_implicit_target_a, :integer, source: :EffectImplicitTargetA)
    field(:effect_implicit_target_b, :integer, source: :EffectImplicitTargetB)
    field(:effect_radius_index, :integer, source: :EffectRadiusIndex)
    field(:effect_item_type, :integer, source: :EffectItemType)
    field(:effect_misc_value, :integer, source: :EffectMiscValue)
    field(:effect_trigger_spell, :integer, source: :EffectTriggerSpell)
    field(:effect_die_sides, :integer, source: :EffectDieSides)
    field(:effect_base_dice, :integer, source: :EffectBaseDice)
    field(:effect_base_points, :integer, source: :EffectBasePoints)
    field(:effect_amplitude, :integer, source: :EffectAmplitude)
    field(:effect_chain_target, :integer, source: :EffectChainTarget)
    field(:effect_dice_per_level, :float, source: :EffectDicePerLevel)
    field(:effect_real_points_per_level, :float, source: :EffectRealPointsPerLevel)
    field(:effect_points_per_combo, :float, source: :EffectPointsPerComboPoint)
    field(:effect_multiple_value, :float, source: :EffectMultipleValue)
  end
end
