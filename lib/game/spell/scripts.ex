defmodule ThistleTea.Game.Spell.Scripts do
  @moduledoc """
  Per-spell rules that 1.12 data cannot express, mirroring the reference
  cores' spell scripts. Vanilla has no precast links — Power Word: Shield
  applying Weakened Soul is hardcoded even in MaNGOS — so `apply_trigger/1`
  carries those pairs, keyed by chain so every rank matches. (The re-shield
  *block* needs no script: Weakened Soul is a mechanic-19 immunity in the DBC
  and the shield is mechanic 19, so generic immunity handling covers it.)
  `exclusive_category/1` classifies raw DBC rows whose mutual exclusivity the
  data likewise never states.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell

  @power_word_shield 17
  @weakened_soul 6788

  @apply_triggers %{@power_word_shield => @weakened_soul}

  @battle_stance_form 17
  @defensive_stance_form 18
  @berserker_stance_form 19

  @shapeshift_passives %{
    @battle_stance_form => 21_156,
    @defensive_stance_form => 7_376,
    @berserker_stance_form => 7_381
  }

  @spell_family_mage 3
  @mage_armor_family_flags 0x12000000
  @warlock_armor_visual 130
  @warlock_armor_icon 89

  def apply_trigger(%Spell{} = spell) do
    Map.get(@apply_triggers, chain_id(spell))
  end

  def shapeshift_passive(form), do: Map.get(@shapeshift_passives, form)

  @overpower_ranks [7384, 7887, 11_584, 11_585]
  @execute_ranks [5308, 20_658, 20_660, 20_661, 20_662]
  @execute_damage_spell 20_647

  def requires_combo_target?(%Spell{id: id}), do: id in @overpower_ranks
  def requires_combo_target?(_spell), do: false

  def dummy_effect(%Spell{id: id}) when id in @execute_ranks, do: :execute
  def dummy_effect(_spell), do: nil

  def execute_damage_spell_id, do: @execute_damage_spell

  def exclusive_category(row) do
    cond do
      row.spell_class_set == @spell_family_mage and
          ((row.spell_class_mask_0 || 0) &&& @mage_armor_family_flags) != 0 ->
        :mage_armor

      row.spell_visual_0 == @warlock_armor_visual and row.spell_icon == @warlock_armor_icon ->
        :warlock_armor

      true ->
        nil
    end
  end

  defp chain_id(%Spell{first_in_chain: first}) when is_integer(first) and first > 0, do: first
  defp chain_id(%Spell{id: id}), do: id
end
