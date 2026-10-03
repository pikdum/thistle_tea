defmodule ThistleTea.Game.Core.Spell.Scripts do
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

  alias ThistleTea.Game.Core.Class.Druid
  alias ThistleTea.Game.Core.Class.Paladin
  alias ThistleTea.Game.Core.Class.Priest
  alias ThistleTea.Game.Core.Class.Shaman
  alias ThistleTea.Game.Core.Class.Warlock
  alias ThistleTea.Game.Core.Profession.Engineering.DeathRay
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cone
  alias ThistleTea.Game.Core.Spell.Consumable
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Slow

  @battle_stance_form 17
  @defensive_stance_form 18
  @berserker_stance_form 19

  @dream_dragon_mark_stuns [{25_040, 25_043}, {23_182, 23_186}]

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
  @mage_magic_family_flag 0x00002000
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

  @immediate_periodic_spells [8145, 6474, 8179, 8172, 8167, 8515, 10_609, 10_612]
  @preserved_periodic_timers @immediate_periodic_spells ++ [13_797, 14_298, 14_299, 14_300, 14_301, 23_184, 25_041]
  @shadow_bolt_whirl [24_820, 24_821, 24_822, 24_823, 24_835, 24_836, 24_837, 24_838]

  def cone(spell_id, _degrees) when spell_id in @shadow_bolt_whirl do
    step = Enum.find_index(@shadow_bolt_whirl, &(&1 == spell_id))
    %Cone{degrees: 120, offset_radians: step * :math.pi() / 4}
  end

  def cone(_spell_id, degrees), do: %Cone{degrees: degrees}

  def periodic_trigger_spell_id(%Spell{id: 24_834}, _trigger_id, tick_count) do
    Enum.at(@shadow_bolt_whirl, rem(tick_count, length(@shadow_bolt_whirl)))
  end

  def periodic_trigger_spell_id(_spell, trigger_id, _tick_count), do: trigger_id

  def initial_periodic_delay(%Spell{id: id}, _interval) when id in @immediate_periodic_spells, do: 0
  def initial_periodic_delay(%Spell{}, interval), do: interval

  def preserve_periodic_timer?(%Spell{stack_amount: cap}) when is_integer(cap) and cap > 0, do: true
  def preserve_periodic_timer?(%Spell{spell_visual: 0, spell_icon: 689}), do: true
  def preserve_periodic_timer?(%Spell{id: id}), do: id in @preserved_periodic_timers

  def apply_trigger(%Spell{} = spell) do
    cond do
      trigger_id = Priest.shield_trigger_id(spell) -> trigger_id
      Spell.vmangos_script?(spell, "spell_paladin_bubble") -> Paladin.forbearance_id()
      Spell.vmangos_script?(spell, "spell_first_aid") -> 11_196
      true -> nil
    end
  end

  def shapeshift_passives(form), do: Map.get(@shapeshift_passives, form, [])

  def boost_aura_ids(%Spell{id: 19_574, spell_family: @spell_family_hunter}), do: [24_395, 24_396, 24_397, 26_592]
  def boost_aura_ids(_spell), do: []

  defdelegate form_aura_ids(spell), to: Druid
  defdelegate script_spell_ids(spell), to: Shaman
  defdelegate form_aura_spell(parent, spell), to: Druid

  @overpower_family_mask 0x00000004
  @execute_damage_spell 20_647
  @blade_flurry_radius_yards 5.0
  @last_stand 12_975
  @preparation 14_185
  @last_stand_health_buff 12_976
  @last_stand_health_fraction 0.3
  @tame_beast_completion 13_535
  @tame_beast_ownership 13_481

  def channel_trigger_spell_id(%Spell{id: 1515}, @tame_beast_completion), do: @tame_beast_ownership
  def channel_trigger_spell_id(_spell, trigger_spell_id), do: trigger_spell_id

  def channel_start_trigger(%Spell{} = spell) do
    if Spell.vmangos_script?(spell, "spell_gdr_channel"), do: 13_493
  end

  @script_finish_triggers %{"spell_cannibalize" => 20_578, "spell_wolfshead_helm" => 29_940}

  def successful_finish_trigger(%Spell{script_name: script_name}) when is_map_key(@script_finish_triggers, script_name),
    do: Map.fetch!(@script_finish_triggers, script_name)

  def successful_finish_trigger(%Spell{} = spell), do: Priest.holy_nova_heal_id(spell)

  def successful_finish_trigger(_spell), do: nil

  def shared_damage_effects(%Spell{} = spell) do
    if Spell.vmangos_script?(spell, "spell_meteor"), do: [0], else: []
  end

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
  def dummy_effect(%Spell{id: id}) when id in [12_162, 12_850, 12_868], do: :deep_wounds
  def dummy_effect(%Spell{id: 20_572}), do: :blood_fury
  def dummy_effect(%Spell{spell_family: 0, spell_icon: 1661}), do: :berserking
  def dummy_effect(%Spell{id: 29_518}), do: :silithyst_pickup
  def dummy_effect(%Spell{id: 30_176}), do: :silithyst_pvp
  def dummy_effect(%Spell{id: @tame_beast_completion}), do: :tame_beast_completion
  def dummy_effect(%Spell{id: @preparation}), do: :preparation
  def dummy_effect(%Spell{id: 9033, spell_family: 7}), do: :shapeshift_cleanse
  def dummy_effect(%Spell{id: 13_120}), do: :net_o_matic
  def dummy_effect(%Spell{id: 14_537}), do: :six_demon_bag
  def dummy_effect(%Spell{id: 8344}), do: :universal_remote
  def dummy_effect(%Spell{id: 13_180}), do: :mind_control_cap
  def dummy_effect(%Spell{id: 23_134}), do: :goblin_bomb
  def dummy_effect(%Spell{id: 23_453}), do: :gnomish_transporter
  def dummy_effect(%Spell{id: 23_448}), do: :transporter_arrival
  def dummy_effect(%Spell{id: 25_860}), do: :reindeer_transformation
  def dummy_effect(%Spell{id: 28_006}), do: {:trigger_spell, 29_296}
  def dummy_effect(%Spell{id: 28_091}), do: :spirit_spawn_out
  def dummy_effect(%Spell{id: 28_345}), do: {:trigger_spell, 28_281}
  def dummy_effect(%Spell{id: id}) when id in [23_185, 25_044], do: {:dream_dragon_aura, @dream_dragon_mark_stuns}
  def dummy_effect(%Spell{id: 21_147}), do: {:arcane_vacuum, 21_150}
  def dummy_effect(%Spell{id: id}) when id in [11_885, 11_886, 11_887, 11_888, 11_889, 12_699], do: :capture_corpse
  def dummy_effect(%Spell{id: 8593}), do: {:restore_to_life, 120_000}
  def dummy_effect(%Spell{id: 15_998}), do: :capture_creature
  def dummy_effect(%Spell{id: 17_271}), do: :item_self_outcome

  @guardian_trinkets %{23_074 => 19_804, 23_075 => 12_749, 23_076 => 4073, 23_133 => 13_166}

  def dummy_effect(%Spell{id: id}) when is_map_key(@guardian_trinkets, id),
    do: {:guardian_trinket, Map.fetch!(@guardian_trinkets, id)}

  @script_dummy_effects %{
    "spell_deviate_fish" => {:random_consumable, :deviate_fish},
    "spell_cooked_deviate_fish" => {:random_consumable, :savory_deviate_delight},
    "spell_noggenfogger_elixir" => {:random_consumable, :noggenfogger},
    "spell_brittle_armor_dummy" => {:trigger_spell, 24_575},
    "spell_mercurial_shield_dummy" => {:trigger_spell, 26_464},
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

  def trigger_chance(%Spell{script_name: "spell_linkens_boomerang"}, %Effect{index: 1}), do: {1, 31}
  def trigger_chance(%Spell{script_name: "spell_linkens_boomerang"}, %Effect{index: 2}), do: {1, 11}
  def trigger_chance(%Spell{script_name: "spell_scorpid_surprise"}, %Effect{index: 1}), do: {1, 11}
  def trigger_chance(_spell, _effect), do: nil

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

  def aura_amount_override(%Spell{} = spell, _entity), do: DeathRay.aura_amount(spell)

  @dispel_poison 4
  @mod_confuse_aura 5
  @prevention_silence 1
  @judgement_family_flags 0x20180400
  @judgement_of_command_icon 561
  @judgement_of_command_visual 5652
  @positive_shout_flags_0 0x00010000
  @positive_shout_flags_1 0x00008000

  def exclusive_category(row, elixir_mask \\ 0) do
    Consumable.category(row) || generic_exclusive_category(row) || mage_exclusive_category(row) ||
      paladin_exclusive_category(row) || warlock_exclusive_category(row) || Consumable.elixir_category(elixir_mask) ||
      Slow.category(row)
  end

  defp generic_exclusive_category(%{id: id}) when id in [28_418, 28_419, 28_420], do: :generals_warcry

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

  defp mage_exclusive_category(%{spell_class_set: @spell_family_mage, spell_class_mask_0: flags}) do
    flags = flags || 0

    cond do
      (flags &&& @mage_armor_family_flags) != 0 -> :mage_armor
      (flags &&& @mage_magic_family_flag) != 0 -> :mage_magic
      true -> nil
    end
  end

  defp mage_exclusive_category(_row), do: nil

  defp warlock_exclusive_category(row) do
    cond do
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
