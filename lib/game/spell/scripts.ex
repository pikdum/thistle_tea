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

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell

  @power_word_shield 17
  @weakened_soul 6788
  @forbearance 25_771

  @apply_triggers %{
    @power_word_shield => @weakened_soul,
    498 => @forbearance,
    642 => @forbearance,
    1022 => @forbearance
  }

  @battle_stance_form 17
  @defensive_stance_form 18
  @berserker_stance_form 19

  @shapeshift_passives %{
    1 => [3025],
    3 => [5419],
    4 => [5421],
    5 => [1178, 21_178],
    8 => [9635, 21_178],
    @battle_stance_form => [21_156],
    @defensive_stance_form => [7376],
    @berserker_stance_form => [7381],
    31 => [24_905]
  }

  @spell_family_mage 3
  @spell_family_warlock 5
  @spell_family_paladin 10
  @mage_armor_family_flags 0x12000000
  @paladin_seal_family_flags 0x0A000200
  @paladin_blessing_family_flags 0x10000100
  @warlock_armor_visual 130
  @warlock_armor_icon 89

  def apply_trigger(%Spell{} = spell) do
    Map.get(@apply_triggers, chain_id(spell))
  end

  def shapeshift_passives(form), do: Map.get(@shapeshift_passives, form, [])

  @overpower_ranks [7384, 7887, 11_584, 11_585]
  @execute_ranks [5308, 20_658, 20_660, 20_661, 20_662]
  @execute_damage_spell 20_647
  @bloodthirst_ranks [23_881, 23_892, 23_893, 23_894]
  @last_stand 12_975
  @preparation 14_185
  @holy_shock %{
    20_473 => %{damage: 25_912, heal: 25_914},
    20_929 => %{damage: 25_911, heal: 25_913},
    20_930 => %{damage: 25_902, heal: 25_903}
  }
  @last_stand_health_buff 12_976
  @last_stand_health_fraction 0.3
  @soul_link 19_028
  @rogue_finishers [
    408,
    8643,
    6760,
    6761,
    6762,
    8623,
    8624,
    11_299,
    11_300,
    8647,
    8649,
    8650,
    11_197,
    11_198,
    1943,
    8639,
    8640,
    11_273,
    11_274,
    11_275,
    5171,
    6774
  ]

  def requires_combo_target?(%Spell{id: id}), do: id in @overpower_ranks or id in @rogue_finishers
  def requires_combo_target?(_spell), do: false

  def dummy_effect(%Spell{id: id}) when id in @execute_ranks, do: :execute
  def dummy_effect(%Spell{id: @last_stand}), do: :last_stand
  def dummy_effect(%Spell{id: @preparation}), do: :preparation
  def dummy_effect(%Spell{id: id}) when is_map_key(@holy_shock, id), do: {:holy_shock, Map.fetch!(@holy_shock, id)}
  def dummy_effect(%Spell{name: "Judgement of Command"}), do: :judgement_of_command
  def dummy_effect(%Spell{id: @soul_link}), do: :soul_link

  def dummy_effect(%Spell{} = spell) do
    if Warlock.life_tap?(spell), do: :life_tap
  end

  def dummy_effect(_spell), do: nil

  def execute_damage_spell_id, do: @execute_damage_spell

  def blocked_by_aura?(%Spell{id: id}, entity) when id in [498, 5573, 642, 1020, 1022, 5599, 10_278] do
    Aura.has_spell?(entity, @forbearance)
  end

  def blocked_by_aura?(_spell, _entity), do: false

  def paladin_judgement?(%Spell{spell_family: @spell_family_paladin, family_flags_0: flags}) when is_integer(flags),
    do: (flags &&& 0x00800000) != 0

  def paladin_judgement?(_spell), do: false

  def last_stand_health_buff_id, do: @last_stand_health_buff

  def ap_percent_damage?(%Spell{id: id}), do: id in @bloodthirst_ranks
  def ap_percent_damage?(_spell), do: false

  def finisher?(%Spell{id: id}), do: id in @rogue_finishers
  def finisher?(_spell), do: false

  def finisher_duration_ms(%Spell{name: "Slice and Dice"}, points), do: 6_000 + points * 3_000
  def finisher_duration_ms(%Spell{name: "Rupture"}, points), do: 4_000 + points * 2_000
  def finisher_duration_ms(%Spell{name: "Kidney Shot"}, points), do: points * 1_000
  def finisher_duration_ms(_spell, _points), do: nil

  def aura_amount_override(%Spell{id: @last_stand_health_buff}, %{unit: %{max_health: max_health}})
      when is_integer(max_health) do
    trunc(max_health * @last_stand_health_fraction)
  end

  def aura_amount_override(_spell, _entity), do: nil

  def exclusive_category(row) do
    cond do
      shapeshift_spell?(row) -> :shapeshift
      hunter_aspect?(row) -> :hunter_aspect
      shaman_shield?(row) -> :shaman_shield
      true -> paladin_exclusive_category(row) || non_paladin_exclusive_category(row)
    end
  end

  defp shapeshift_spell?(row) do
    Enum.any?(0..2, &(Map.get(row, :"effect_aura_#{&1}") == 36))
  end

  defp hunter_aspect?(row), do: String.starts_with?(Map.get(row, :name_en_gb) || "", "Aspect of the ")

  defp shaman_shield?(row), do: (Map.get(row, :name_en_gb) || "") in ["Lightning Shield", "Water Shield"]

  defp non_paladin_exclusive_category(row) do
    cond do
      row.spell_class_set == @spell_family_mage and
          ((row.spell_class_mask_0 || 0) &&& @mage_armor_family_flags) != 0 ->
        :mage_armor

      row.spell_visual_0 == @warlock_armor_visual and row.spell_icon == @warlock_armor_icon ->
        :warlock_armor

      warlock_curse?(row) ->
        :warlock_curse

      true ->
        nil
    end
  end

  defp warlock_curse?(row) do
    row.spell_class_set == @spell_family_warlock and String.starts_with?(row.name_en_gb || "", "Curse of")
  end

  defp paladin_exclusive_category(row) do
    cond do
      paladin_family_flag?(row, @paladin_seal_family_flags) -> :paladin_seal
      paladin_family_flag?(row, @paladin_blessing_family_flags) -> :paladin_blessing
      paladin_area_aura?(row) -> :paladin_aura
      true -> nil
    end
  end

  defp paladin_family_flag?(row, mask) do
    row.spell_class_set == @spell_family_paladin and ((row.spell_class_mask_0 || 0) &&& mask) != 0
  end

  defp paladin_area_aura?(row) do
    row.spell_class_set == @spell_family_paladin and
      Enum.any?(0..2, &(Map.get(row, :"effect_#{&1}") == 35))
  end

  defp chain_id(%Spell{first_in_chain: first}) when is_integer(first) and first > 0, do: first
  defp chain_id(%Spell{id: id}), do: id
end
