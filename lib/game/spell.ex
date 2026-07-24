defmodule ThistleTea.Game.Spell do
  @moduledoc """
  Internal spell struct translated from the spell DBC: attributes, effects,
  rank-chain and exclusive-category info, plus school-mask helpers.
  """
  import Bitwise, only: [<<<: 2, &&&: 2]

  alias ThistleTea.Game.Spell.Effect

  defstruct [
    :id,
    :name,
    :spell_icon,
    :spell_visual,
    :script_name,
    :proc_rule,
    :school,
    :cast_time_ms,
    :duration_ms,
    :max_duration_ms,
    :range_yards,
    :mana_cost,
    :mana_cost_per_second,
    :mana_cost_per_second_per_level,
    :power_type,
    :gcd_ms,
    :dispel_type,
    :first_in_chain,
    :rank,
    :exclusive_category,
    spell_family: 0,
    spell_level: 0,
    base_level: 0,
    max_level: 0,
    custom_flags: 0,
    family_flags_0: 0,
    family_flags_1: 0,
    mechanic: 0,
    stances_not: 0,
    min_range_yards: 0.0,
    prevention_type: 0,
    proc_chance: 0,
    proc_charges: 0,
    proc_type_mask: 0,
    speed: 0.0,
    mana_cost_percent: 0,
    dmg_class: 0,
    stances: 0,
    caster_aura_state: 0,
    target_aura_state: 0,
    target_creature_type_mask: 0,
    stack_amount: 0,
    category: 0,
    recovery_time_ms: 0,
    category_recovery_time_ms: 0,
    aura_interrupt_flags: 0,
    interrupt_flags: 0,
    channel_interrupt_flags: 0,
    equipped_item_class: -1,
    equipped_item_subclass_mask: 0,
    attributes: MapSet.new(),
    effects: [],
    script_steps: [],
    reagents: []
  ]

  def attribute?(%__MODULE__{attributes: attrs}, attr), do: MapSet.member?(attrs, attr)

  def level_units(%__MODULE__{} = spell, caster_level) when is_integer(caster_level) and caster_level > 0 do
    caster_level
    |> min_level_cap(spell.max_level)
    |> max(spell.base_level || 0)
    |> Kernel.-(spell.spell_level || 0)
  end

  def level_units(_spell, _caster_level), do: 0

  defp min_level_cap(level, max_level) when is_integer(max_level) and max_level > 0, do: min(level, max_level)
  defp min_level_cap(level, _max_level), do: level

  def breaks_on_damage?(%__MODULE__{aura_interrupt_flags: flags}) when is_integer(flags), do: (flags &&& 0x2) != 0
  def breaks_on_damage?(_spell), do: false

  def pushback_on_damage?(%__MODULE__{interrupt_flags: flags}) when is_integer(flags), do: (flags &&& 0x02) != 0
  def pushback_on_damage?(_spell), do: false

  def cancels_on_damage?(%__MODULE__{interrupt_flags: flags}) when is_integer(flags), do: (flags &&& 0x10) != 0
  def cancels_on_damage?(_spell), do: false

  def channel_delayed_on_damage?(%__MODULE__{channel_interrupt_flags: flags}) when is_integer(flags) do
    (flags &&& 0x4000) != 0
  end

  def channel_delayed_on_damage?(_spell), do: false

  def channel_cancels_on_damage?(%__MODULE__{channel_interrupt_flags: flags}) when is_integer(flags) do
    (flags &&& 0x02) != 0
  end

  def channel_cancels_on_damage?(_spell), do: false

  def usable_in_stance?(%__MODULE__{stances: stances}, _form) when stances in [0, nil], do: true

  def usable_in_stance?(%__MODULE__{stances: stances}, form) when is_integer(form) and form > 0 do
    (stances &&& 1 <<< (form - 1)) != 0
  end

  def usable_in_stance?(_spell, _form), do: false

  @custom_flags %{
    allow_stack_between_caster: 0x001,
    negative: 0x002,
    positive: 0x004,
    chan_no_dist_limit: 0x008,
    fixed_damage: 0x010,
    ignore_armor: 0x020,
    behind_target: 0x040,
    face_target: 0x080,
    single_target_aura: 0x100,
    aura_apply_breaks_stealth: 0x200,
    not_removed_on_evade: 0x400,
    send_channel_visual: 0x800,
    separate_aura_per_caster: 0x1000,
    trigger_weapon_procs: 0x2000
  }

  def custom?(%__MODULE__{custom_flags: flags}, flag) when is_integer(flags) do
    (flags &&& Map.fetch!(@custom_flags, flag)) != 0
  end

  def custom?(_spell, _flag), do: false

  @stance_like_forms [17, 18, 19, 28, 30, 31]

  def shapeshift_cast_error(%__MODULE__{} = spell, form) do
    form = if is_integer(form), do: form, else: 0
    stance_mask = if form > 0, do: 1 <<< (form - 1), else: 0
    stances = spell.stances || 0

    cond do
      (stance_mask &&& (spell.stances_not || 0)) != 0 -> {:error, :not_shapeshift}
      (stance_mask &&& stances) != 0 -> :ok
      true -> shapeshifted_cast_error(spell, stances, acts_as_shifted?(form))
    end
  end

  defp shapeshifted_cast_error(spell, stances, true) do
    cond do
      attribute?(spell, :not_while_shapeshifted) -> {:error, :not_shapeshift}
      stances != 0 -> {:error, :only_shapeshift}
      true -> :ok
    end
  end

  defp shapeshifted_cast_error(spell, stances, false) do
    if stances != 0 and not attribute?(spell, :allow_while_not_shapeshifted) do
      {:error, :only_shapeshift}
    else
      :ok
    end
  end

  defp acts_as_shifted?(form), do: form > 0 and form not in @stance_like_forms

  def stance_like_forms, do: @stance_like_forms

  def same_chain?(%__MODULE__{id: id1, first_in_chain: first1}, %__MODULE__{id: id2, first_in_chain: first2}) do
    id1 != id2 and is_integer(first1) and first1 == first2
  end

  def stronger_rank_of_same_chain?(%__MODULE__{rank: rank1} = spell1, %__MODULE__{rank: rank2} = spell2) do
    same_chain?(spell1, spell2) and is_integer(rank1) and is_integer(rank2) and rank1 > rank2
  end

  def same_exclusive_category?(%__MODULE__{id: id1, exclusive_category: cat1}, %__MODULE__{
        id: id2,
        exclusive_category: cat2
      }) do
    id1 != id2 and not is_nil(cat1) and cat1 == cat2
  end

  def school_mask(%__MODULE__{school: school}), do: school_mask(school)
  def school_mask(:physical), do: school_mask_index(0)
  def school_mask(:holy), do: school_mask_index(1)
  def school_mask(:fire), do: school_mask_index(2)
  def school_mask(:nature), do: school_mask_index(3)
  def school_mask(:frost), do: school_mask_index(4)
  def school_mask(:shadow), do: school_mask_index(5)
  def school_mask(:arcane), do: school_mask_index(6)
  def school_mask(school) when is_integer(school), do: school_mask_index(school)
  def school_mask(_school), do: 0

  def school_index(%__MODULE__{school: school}), do: school_index(school)
  def school_index(:physical), do: 0
  def school_index(:holy), do: 1
  def school_index(:fire), do: 2
  def school_index(:nature), do: 3
  def school_index(:frost), do: 4
  def school_index(:shadow), do: 5
  def school_index(:arcane), do: 6
  def school_index(school) when is_integer(school), do: school
  def school_index(_school), do: 0

  defp school_mask_index(school) when is_integer(school) and school >= 0, do: 1 <<< school
  defp school_mask_index(_school), do: 0

  def requires_hostile_target?(%__MODULE__{effects: effects}) do
    Enum.any?(effects, fn %Effect{implicit_target_a: a, implicit_target_b: b} ->
      a == :target_enemy or b == :target_enemy
    end)
  end

  def targets_hostile_units?(%__MODULE__{effects: effects}) do
    Enum.any?(effects, fn %Effect{implicit_target_a: a, implicit_target_b: b} ->
      hostile_implicit_target?(a) or hostile_implicit_target?(b)
    end)
  end

  defp hostile_implicit_target?(target) do
    target in [
      :target_enemy,
      :aoe_enemy_at_caster,
      :aoe_enemy_at_dest,
      :aoe_enemy_in_cone,
      :aoe_enemy_at_channel
    ]
  end

  def requires_friendly_target?(%__MODULE__{effects: effects}) do
    Enum.any?(effects, fn %Effect{implicit_target_a: a, implicit_target_b: b} ->
      a == :target_ally or b == :target_ally
    end)
  end

  def harmful?(%__MODULE__{} = spell) do
    targets_hostile_units?(spell) or damage_effects(spell) != []
  end

  def harmful?(_spell), do: false

  def resurrect_spell?(%__MODULE__{effects: effects}) do
    Enum.any?(effects, &match?(%Effect{type: type} when type in [:resurrect, :resurrect_new], &1))
  end

  def aura_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: type} when type in [:apply_aura, :apply_area_aura], &1))
  end

  @damage_effect_types [
    :school_damage,
    :weapon_damage,
    :weapon_damage_noschool,
    :normalized_weapon_damage,
    :weapon_percent_damage
  ]

  @weapon_damage_effect_types [
    :weapon_damage,
    :weapon_damage_noschool,
    :normalized_weapon_damage,
    :weapon_percent_damage
  ]

  @proc_type_masks %{
    deal_melee_swing: 0x00000004,
    deal_melee_ability: 0x00000010
  }

  def damage_effects(%__MODULE__{effects: effects}) do
    Enum.filter(effects, &match?(%Effect{type: type} when type in @damage_effect_types, &1))
  end

  def weapon_damage_effect_types, do: @weapon_damage_effect_types

  def melee_ability?(%__MODULE__{dmg_class: 2}), do: true
  def melee_ability?(_spell), do: false

  def ranged_ability?(%__MODULE__{dmg_class: 3}), do: true
  def ranged_ability?(_spell), do: false

  def procs_on?(%__MODULE__{proc_type_mask: mask}, proc_type) when is_integer(mask) do
    case Map.fetch(@proc_type_masks, proc_type) do
      {:ok, proc_mask} -> (mask &&& proc_mask) != 0
      :error -> false
    end
  end

  def procs_on?(_spell, _proc_type), do: false

  def family_flag?(%__MODULE__{spell_family: family, family_flags_0: flags}, family, mask, 0)
      when is_integer(flags) and is_integer(mask), do: (flags &&& mask) != 0

  def family_flag?(%__MODULE__{spell_family: family, family_flags_1: flags}, family, mask, 1)
      when is_integer(flags) and is_integer(mask), do: (flags &&& mask) != 0

  def family_flag?(_spell, _family, _mask, _word), do: false

  def family_flag?(%__MODULE__{} = spell, family, mask), do: family_flag?(spell, family, mask, 0)

  def vmangos_script?(%__MODULE__{script_name: script_name}, script_name) when is_binary(script_name), do: true
  def vmangos_script?(_spell, _script_name), do: false

  def creature_type_allowed?(%__MODULE__{target_creature_type_mask: mask}, creature_type)
      when is_integer(mask) and mask > 0 and is_integer(creature_type) and creature_type > 0 do
    (mask &&& 1 <<< (creature_type - 1)) != 0
  end

  def creature_type_allowed?(%__MODULE__{target_creature_type_mask: mask}, _creature_type) when mask in [0, nil],
    do: true

  def creature_type_allowed?(_spell, _creature_type), do: false

  def channel_tick_ms(%__MODULE__{effects: effects}) do
    effects
    |> Enum.map(& &1.amplitude_ms)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.min(fn -> 1_000 end)
  end

  def duration_for_combo_points(%__MODULE__{duration_ms: duration, max_duration_ms: max_duration}, combo_points)
      when is_integer(duration) and is_integer(max_duration) and is_integer(combo_points) and combo_points > 0 do
    duration + div((max_duration - duration) * min(combo_points, 5), 5)
  end

  def duration_for_combo_points(%__MODULE__{duration_ms: duration}, _combo_points), do: duration
end
