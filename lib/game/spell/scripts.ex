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

  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.Priest
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell

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
  @spell_family_warrior 4
  @spell_family_warlock 5
  @spell_family_hunter 9
  @spell_family_paladin 10
  @spell_family_shaman 11
  @mage_armor_family_flags 0x12000000
  @paladin_seal_family_flags 0x0A000200
  @paladin_blessing_family_flags 0x10000100
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
    cond do
      trigger_id = Priest.shield_trigger_id(spell) -> trigger_id
      Spell.vmangos_script?(spell, "spell_paladin_bubble") -> Paladin.forbearance_id()
      true -> nil
    end
  end

  def shapeshift_passives(form), do: Map.get(@shapeshift_passives, form, [])

  @overpower_family_mask 0x00000004
  @execute_damage_spell 20_647
  @blade_flurry_radius_yards 5.0
  @last_stand 12_975
  @preparation 14_185
  @last_stand_health_buff 12_976
  @last_stand_health_fraction 0.3
  @tame_beast_completion 13_535
  @tame_beast_ownership 13_481

  def successful_finish_trigger(%Spell{} = spell), do: Priest.holy_nova_heal_id(spell)
  def successful_finish_trigger(_spell), do: nil

  def proc_trigger_spell_id(%Spell{} = spell, triggering_spell_id) do
    if Priest.touch_of_weakness?(spell) do
      Priest.touch_of_weakness_damage_id(triggering_spell_id)
    else
      spell.id
    end
  end

  def proc_trigger_spell_id(_spell, _triggering_spell_id), do: nil

  def incoming_proc_trigger(%Spell{id: id} = spell, default_spell_id, owner_guid, attacker_guid) do
    if Paladin.judgement_proc_aura?(spell) do
      {attacker_guid, attacker_guid, Paladin.judgement_proc_id(id)}
    else
      {owner_guid, attacker_guid, default_spell_id}
    end
  end

  def incoming_proc_trigger(_spell, default_spell_id, owner_guid, attacker_guid),
    do: {owner_guid, attacker_guid, default_spell_id}

  def requires_combo_target?(%Spell{} = spell),
    do: warrior_family_flag?(spell, @overpower_family_mask) or finisher?(spell)

  def requires_combo_target?(_spell), do: false

  def dummy_effect(%Spell{id: @last_stand}), do: :last_stand
  def dummy_effect(%Spell{id: @tame_beast_completion}), do: :tame_beast_completion
  def dummy_effect(%Spell{id: @preparation}), do: :preparation

  @script_dummy_effects %{
    "spell_paladin_judgement_of_command_dummy" => :judgement_of_command,
    "spell_warrior_execute_dummy" => :execute,
    "spell_hunter_readiness" => :hunter_cooldowns,
    "spell_hunter_refocus" => :hunter_cooldowns,
    "spell_druid_enrage" => :druid_enrage,
    "spell_mage_cold_snap" => :mage_cold_snap
  }

  def dummy_effect(%Spell{id: id, script_name: script_name} = spell) do
    cond do
      Spell.vmangos_script?(spell, "spell_paladin_holy_shock") and is_map(Paladin.holy_shock_ids(id)) ->
        {:holy_shock, Paladin.holy_shock_ids(id)}

      is_binary(script_name) and is_map_key(@script_dummy_effects, script_name) ->
        Map.fetch!(@script_dummy_effects, script_name)

      Warlock.life_tap?(spell) ->
        :life_tap

      true ->
        nil
    end
  end

  def dummy_effect(_spell), do: nil

  def tame_beast_ownership_spell_id, do: @tame_beast_ownership

  def judgement_of_command_damage?(%Spell{} = spell),
    do: Spell.vmangos_script?(spell, "spell_paladin_judgement_of_command_damage")

  def judgement_of_command_damage?(_spell), do: false

  def uses_melee_spell_crit?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_paladin_hammer_of_wrath")

  def uses_melee_spell_crit?(_spell), do: false

  def execute_damage_spell_id, do: @execute_damage_spell
  def blade_flurry_radius_yards, do: @blade_flurry_radius_yards

  def paladin_judgement?(%Spell{spell_family: @spell_family_paladin, family_flags_0: flags}) when is_integer(flags),
    do: (flags &&& 0x00800000) != 0

  def paladin_judgement?(_spell), do: false

  def last_stand_health_buff_id, do: @last_stand_health_buff

  def ap_percent_damage?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_warrior_bloodthirst")
  def ap_percent_damage?(_spell), do: false

  def finisher?(%Spell{} = spell), do: Spell.attribute?(spell, :finishing_move)
  def finisher?(_spell), do: false

  def aura_amount_override(%Spell{id: @last_stand_health_buff}, %{unit: %{max_health: max_health}})
      when is_integer(max_health) do
    trunc(max_health * @last_stand_health_fraction)
  end

  def aura_amount_override(_spell, _entity), do: nil

  @dispel_poison 4
  @mod_confuse_aura 5
  @prevention_silence 1
  @judgement_family_flags 0x20180400
  @judgement_of_command_icon 561
  @judgement_of_command_visual 5652
  @positive_shout_flags_0 0x00010000
  @positive_shout_flags_1 0x00008000

  def exclusive_category(row) do
    generic_exclusive_category(row) || paladin_exclusive_category(row) || non_paladin_exclusive_category(row)
  end

  defp generic_exclusive_category(row) do
    cond do
      shapeshift_spell?(row) -> :shapeshift
      hunter_aspect?(row) -> :hunter_aspect
      hunter_sting?(row) -> :hunter_sting
      shaman_shield?(row) -> :shaman_shield
      tracking_spell?(row) -> :tracking
      mage_polymorph?(row) -> :mage_polymorph
      positive_shout?(row) -> :positive_shout
      true -> nil
    end
  end

  defp hunter_sting?(row) do
    row.spell_class_set == @spell_family_hunter and row.dispel_type == @dispel_poison
  end

  defp mage_polymorph?(row) do
    row.spell_class_set == @spell_family_mage and Map.get(row, :effect_aura_0) == @mod_confuse_aura and
      Map.get(row, :prevention_type) == @prevention_silence
  end

  defp positive_shout?(row) do
    row.spell_class_set == @spell_family_warrior and
      (((row.spell_class_mask_0 || 0) &&& @positive_shout_flags_0) != 0 or
         ((row.spell_class_mask_1 || 0) &&& @positive_shout_flags_1) != 0)
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
      paladin_judgement_debuff?(row) -> :paladin_judgement
      paladin_area_aura?(row) -> :paladin_aura
      true -> nil
    end
  end

  defp paladin_judgement_debuff?(row) do
    (paladin_family_flag?(row, @judgement_family_flags) and (Map.get(row, :base_level) || 0) != 0) or
      (row.spell_icon == @judgement_of_command_icon and row.spell_visual_0 == @judgement_of_command_visual)
  end

  defp paladin_family_flag?(row, mask) do
    row.spell_class_set == @spell_family_paladin and ((row.spell_class_mask_0 || 0) &&& mask) != 0
  end

  defp paladin_area_aura?(row) do
    row.spell_class_set == @spell_family_paladin and
      Enum.any?(0..2, &(Map.get(row, :"effect_#{&1}") == 35))
  end

  defp warrior_family_flag?(%Spell{spell_family: @spell_family_warrior, family_flags_0: flags}, mask)
       when is_integer(flags), do: (flags &&& mask) != 0

  defp warrior_family_flag?(_spell, _mask), do: false
end
