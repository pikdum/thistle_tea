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
  @spell_family_rogue 8
  @spell_family_warrior 4
  @spell_family_warlock 5
  @spell_family_hunter 9
  @spell_family_paladin 10
  @spell_family_shaman 11
  @mage_armor_family_flags 0x12000000
  @paladin_seal_family_flags 0x0A000200
  @paladin_blessing_family_flags 0x10000100
  @judgement_of_command_icon 561
  @warlock_armor_visual 130
  @warlock_armor_icon 89
  @hunter_aspect_active_icon 122
  @aspect_of_the_beast 13_161
  @auto_shot 75
  @shaman_lightning_shield_family_mask 0x00000400
  @shaman_item_set_lightning_shield 23_552
  @dispel_curse 2
  @tracking_aura_types [44, 45, 151]
  @allow_while_mounted 0x01000000
  @no_autocast_ai 0x00020000

  def apply_trigger(%Spell{} = spell) do
    Map.get(@apply_triggers, chain_id(spell))
  end

  def shapeshift_passives(form), do: Map.get(@shapeshift_passives, form, [])

  @overpower_family_mask 0x00000004
  @bloodthirst_family_mask 0x02000000
  @execute_family_mask 0x20000000
  @execute_damage_spell 20_647
  @rogue_vanish_family_mask 0x00000800
  @rogue_eviscerate_family_mask 0x00020000
  @rogue_stealth_family_mask 0x00400000
  @rogue_misc_family_mask 0x40000000
  @blade_flurry_damage_spell 22_482
  @blade_flurry_radius_yards 5.0
  @last_stand 12_975
  @preparation 14_185
  @holy_shock %{
    20_473 => %{damage: 25_912, heal: 25_914},
    20_929 => %{damage: 25_911, heal: 25_913},
    20_930 => %{damage: 25_902, heal: 25_903}
  }
  @last_stand_health_buff 12_976
  @last_stand_health_fraction 0.3
  def requires_combo_target?(%Spell{} = spell),
    do: warrior_family_flag?(spell, @overpower_family_mask) or finisher?(spell)

  def requires_combo_target?(_spell), do: false

  def dummy_effect(%Spell{id: @last_stand}), do: :last_stand
  def dummy_effect(%Spell{id: @preparation}), do: :preparation
  def dummy_effect(%Spell{id: id}) when is_map_key(@holy_shock, id), do: {:holy_shock, Map.fetch!(@holy_shock, id)}

  def dummy_effect(%Spell{} = spell) do
    cond do
      judgement_of_command_dummy?(spell) -> :judgement_of_command
      warrior_family_flag?(spell, @execute_family_mask) -> :execute
      Warlock.life_tap?(spell) -> :life_tap
      true -> nil
    end
  end

  def dummy_effect(_spell), do: nil

  def judgement_of_command_damage?(%Spell{spell_family: 0, spell_icon: @judgement_of_command_icon} = spell) do
    Enum.any?(spell.effects, &(&1.type == :school_damage))
  end

  def judgement_of_command_damage?(_spell), do: false

  def execute_damage_spell_id, do: @execute_damage_spell
  def blade_flurry_damage_spell_id, do: @blade_flurry_damage_spell
  def blade_flurry_radius_yards, do: @blade_flurry_radius_yards
  def rogue_spell_family, do: @spell_family_rogue

  def rogue_spell?(%Spell{spell_family: @spell_family_rogue}), do: true
  def rogue_spell?(_spell), do: false

  def paladin_judgement?(%Spell{spell_family: @spell_family_paladin, family_flags_0: flags}) when is_integer(flags),
    do: (flags &&& 0x00800000) != 0

  def paladin_judgement?(_spell), do: false

  def last_stand_health_buff_id, do: @last_stand_health_buff

  def ap_percent_damage?(%Spell{} = spell), do: warrior_family_flag?(spell, @bloodthirst_family_mask)
  def ap_percent_damage?(_spell), do: false

  def finisher?(%Spell{} = spell), do: Spell.attribute?(spell, :finishing_move)
  def finisher?(_spell), do: false

  def rogue_vanish?(%Spell{} = spell), do: rogue_family_flag?(spell, @rogue_vanish_family_mask)
  def rogue_vanish?(_spell), do: false

  def rogue_stealth?(%Spell{} = spell), do: rogue_family_flag?(spell, @rogue_stealth_family_mask)
  def rogue_stealth?(_spell), do: false

  def rogue_eviscerate?(%Spell{} = spell), do: rogue_family_flag?(spell, @rogue_eviscerate_family_mask)
  def rogue_eviscerate?(_spell), do: false

  def rogue_blade_flurry?(%Spell{effects: effects} = spell) do
    rogue_family_flag?(spell, @rogue_misc_family_mask) and
      Enum.any?(effects, &(&1.type in [:apply_aura, :apply_area_aura] and &1.aura == :mod_melee_haste))
  end

  def rogue_blade_flurry?(_spell), do: false

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
      tracking_spell?(row) -> :tracking
      true -> paladin_exclusive_category(row) || non_paladin_exclusive_category(row)
    end
  end

  defp shapeshift_spell?(row) do
    Enum.any?(0..2, &(Map.get(row, :"effect_aura_#{&1}") == 36))
  end

  defp hunter_aspect?(%{id: @aspect_of_the_beast}), do: true

  defp hunter_aspect?(row) do
    row.spell_class_set == @spell_family_hunter and row.active_icon == @hunter_aspect_active_icon and
      row.id != @auto_shot
  end

  defp shaman_shield?(%{id: @shaman_item_set_lightning_shield}), do: true

  defp shaman_shield?(row) do
    row.spell_class_set == @spell_family_shaman and
      ((row.spell_class_mask_0 || 0) &&& @shaman_lightning_shield_family_mask) != 0
  end

  defp tracking_spell?(row) do
    tracking_aura? = Enum.any?(0..2, &(Map.get(row, :"effect_aura_#{&1}") in @tracking_aura_types))
    attributes = Map.get(row, :attributes) || 0
    attributes_ex1 = Map.get(row, :attributes_ex1) || 0

    tracking_aura? and
      ((attributes &&& @allow_while_mounted) != 0 or (attributes_ex1 &&& @no_autocast_ai) != 0)
  end

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
    row.spell_class_set == @spell_family_warlock and row.dispel_type == @dispel_curse
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

  defp judgement_of_command_dummy?(
         %Spell{spell_family: @spell_family_paladin, spell_icon: @judgement_of_command_icon} = spell
       ) do
    Enum.any?(spell.effects, &(&1.type == :dummy))
  end

  defp judgement_of_command_dummy?(_spell), do: false

  defp warrior_family_flag?(%Spell{spell_family: @spell_family_warrior, family_flags_0: flags}, mask)
       when is_integer(flags), do: (flags &&& mask) != 0

  defp warrior_family_flag?(_spell, _mask), do: false

  defp rogue_family_flag?(%Spell{spell_family: @spell_family_rogue, family_flags_0: flags}, mask)
       when is_integer(flags), do: (flags &&& mask) != 0

  defp rogue_family_flag?(_spell, _mask), do: false

  defp chain_id(%Spell{first_in_chain: first}) when is_integer(first) and first > 0, do: first
  defp chain_id(%Spell{id: id}), do: id
end
