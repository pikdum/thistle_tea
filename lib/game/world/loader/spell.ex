defmodule ThistleTea.Game.World.Loader.Spell do
  @moduledoc """
  Builds internal spell structs from the spell DBC and derives spellbook data:
  learned spell ids and rank-supersession maps.
  """
  import Bitwise, only: [&&&: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.SpellProcEvent, as: SpellProcEventLoader
  alias ThistleTea.Game.World.Loader.SpellScript, as: SpellScriptLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName, as: SpellScriptNameLoader

  @learn_spell_effect 36
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case DBC.get(Spell, spell_id) do
      nil -> nil
      row -> row |> build() |> put_chain(chain(spell_id))
    end
  end

  def load(_), do: nil

  def chain(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:chain, spell_id}) do
      [{_key, chain}] -> chain
      _ -> cache({:chain, spell_id}, load_chain(spell_id))
    end
  end

  def chain(_spell_id), do: nil

  defp load_chain(spell_id) do
    row =
      Mangos.Repo.all(from(chain in Mangos.SpellChain, where: chain.spell_id == ^spell_id))
      |> select_matching_chain(spell_id)

    case row do
      %Mangos.SpellChain{} = row ->
        %{first_spell: row.first_spell, rank: row.rank, prev_spell: row.prev_spell, req_spell: row.req_spell}

      _ ->
        nil
    end
  end

  defp select_matching_chain(rows, spell_id) do
    current_name = spell_name(spell_id)

    rows
    |> Enum.filter(&(spell_name(&1.first_spell) == current_name))
    |> Enum.max_by(&(&1.rank || 0), fn -> List.first(rows) end)
  end

  defp spell_name(spell_id) do
    case DBC.get(Spell, spell_id) do
      %Spell{name_en_gb: name} -> name
      _ -> nil
    end
  end

  def target_position(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case :ets.lookup(__MODULE__, {:target_position, spell_id}) do
      [{_key, position}] -> position
      _ -> cache({:target_position, spell_id}, load_target_position(spell_id))
    end
  end

  def target_position(_spell_id), do: nil

  defp load_target_position(spell_id) do
    case Mangos.Repo.get(Mangos.SpellTargetPosition, spell_id) do
      %Mangos.SpellTargetPosition{} = row ->
        %{map: row.target_map, x: row.target_position_x, y: row.target_position_y, z: row.target_position_z}

      _ ->
        nil
    end
  end

  defp cache(key, value) do
    :ets.insert(__MODULE__, {key, value})
    value
  end

  def build_spellbook([]), do: %{}

  def build_spellbook(spell_ids) when is_list(spell_ids) do
    spell_ids = Enum.uniq(spell_ids)

    rows =
      DBC.all(
        from(s in Spell,
          where: s.id in ^spell_ids,
          preload: [:spell_cast_time, :spell_duration, :spell_range]
        )
      )

    radius_map = load_radius_map(rows)
    radius_lookup = fn radius_id -> Map.get(radius_map, radius_id) end
    chain_map = load_chain_map(spell_ids)

    rows
    |> Enum.map(&build_preloaded(&1, radius_lookup))
    |> Enum.map(&put_chain(&1, Map.get(chain_map, &1.id)))
    |> Map.new(fn %SpellData{id: id} = spell -> {id, spell} end)
  end

  def build_spellbook(_), do: %{}

  def learned_spell_ids(spell_ids) when is_list(spell_ids) do
    spell_ids = Enum.uniq(spell_ids)

    DBC.all(
      from(s in Spell,
        where: s.id in ^spell_ids,
        select: %{
          id: s.id,
          effect_0: s.effect_0,
          effect_1: s.effect_1,
          effect_2: s.effect_2,
          effect_trigger_spell_0: s.effect_trigger_spell_0,
          effect_trigger_spell_1: s.effect_trigger_spell_1,
          effect_trigger_spell_2: s.effect_trigger_spell_2
        }
      )
    )
    |> Enum.flat_map(&learned_spell_ids_from_row/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def learned_spell_ids(_spell_ids), do: []

  def learned_spell_map(spell_ids) when is_list(spell_ids) do
    spell_ids = Enum.uniq(spell_ids)

    DBC.all(
      from(s in Spell,
        where: s.id in ^spell_ids,
        select: %{
          id: s.id,
          effect_0: s.effect_0,
          effect_1: s.effect_1,
          effect_2: s.effect_2,
          effect_trigger_spell_0: s.effect_trigger_spell_0,
          effect_trigger_spell_1: s.effect_trigger_spell_1,
          effect_trigger_spell_2: s.effect_trigger_spell_2
        }
      )
    )
    |> Map.new(fn row -> {row.id, row |> learned_spell_ids_from_row() |> List.first()} end)
  end

  def learned_spell_map(_spell_ids), do: %{}

  def superseded_by_map(spell_ids) when is_list(spell_ids) do
    spell_ids = Enum.uniq(spell_ids)

    DBC.all(
      from(s in SkillLineAbility,
        where: s.spell in ^spell_ids and s.superseded_by > 0,
        select: {s.spell, s.superseded_by}
      )
    )
    |> Map.new()
  end

  def superseded_by_map(_spell_ids), do: %{}

  defp build(row) do
    row = DBC.preload(row, [:spell_cast_time, :spell_duration, :spell_range])
    build_preloaded(row, &lookup_radius/1)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp build_preloaded(row, radius_lookup) do
    %SpellData{
      id: row.id,
      name: row.name_en_gb,
      spell_icon: row.spell_icon,
      spell_visual: row.spell_visual_0,
      script_name: SpellScriptNameLoader.get(row.id),
      proc_rule: SpellProcEventLoader.get(row.id),
      school: school(row.school),
      cast_time_ms: cast_time_ms(row.spell_cast_time),
      duration_ms: duration_ms(row.spell_duration),
      max_duration_ms: max_duration_ms(row.spell_duration),
      range_yards: range_yards(row.spell_range),
      mana_cost: row.mana_cost || 0,
      mana_cost_per_second: row.mana_cost_per_second || 0,
      mana_cost_per_second_per_level: row.mana_cost_per_second_per_level || 0,
      power_type: row.power_type || 0,
      gcd_ms: row.start_recovery_time || 0,
      dispel_type: row.dispel_type || 0,
      speed: row.speed || 0.0,
      aura_interrupt_flags: row.aura_interrupt_flags || 0,
      mechanic: row.mechanic || 0,
      proc_chance: row.proc_chance || 0,
      proc_charges: row.proc_charges || 0,
      proc_type_mask: row.proc_type_mask || 0,
      attributes: attributes(row.attributes, row.attributes_ex1, row.attributes_ex2, row.attributes_ex3),
      exclusive_category: Scripts.exclusive_category(row),
      spell_family: row.spell_class_set || 0,
      family_flags_0: row.spell_class_mask_0 || 0,
      family_flags_1: row.spell_class_mask_1 || 0,
      description_spell_refs: description_spell_refs(row.description_en_gb),
      effects: build_effects(row, radius_lookup),
      script_steps: SpellScriptLoader.get(row.id),
      reagents: build_reagents(row)
    }
    |> struct!(cooldown_fields(row))
    |> struct!(equipped_item_fields(row))
    |> struct!(power_fields(row))
    |> append_shapeshift_passives(radius_lookup)
  end

  defp description_spell_refs(description) when is_binary(description) do
    ~r/\$(\d+)([a-zA-Z]\d*)/
    |> Regex.scan(description, capture: :all_but_first)
    |> Enum.map(fn [spell_id, variable] -> {String.to_integer(spell_id), variable} end)
  end

  defp description_spell_refs(_description), do: []

  defp power_fields(row) do
    %{
      mana_cost_percent: row.mana_cost_percent || 0,
      dmg_class: row.defence_type || 0,
      stances: row.shapeshift_mask || 0,
      caster_aura_state: row.caster_aura_state || 0,
      target_aura_state: row.target_aura_state || 0,
      target_creature_type_mask: row.target_creature_type || 0,
      stack_amount: row.stack_amount || 0
    }
  end

  defp cooldown_fields(row) do
    %{
      category: row.category || 0,
      recovery_time_ms: row.recovery_time || 0,
      category_recovery_time_ms: row.category_recovery_time || 0
    }
  end

  defp equipped_item_fields(row) do
    %{
      equipped_item_class: signed32(row.equipped_item_class, -1),
      equipped_item_subclass_mask: signed32(row.equipped_item_subclass, 0)
    }
  end

  defp signed32(value, _default) when is_integer(value) do
    <<signed::little-signed-size(32)>> = <<value::little-size(32)>>
    signed
  end

  defp signed32(_value, default), do: default

  defp unsigned32(value) when is_integer(value) and value < 0, do: value + 4_294_967_296
  defp unsigned32(value) when is_integer(value), do: value
  defp unsigned32(_value), do: 0

  defp append_shapeshift_passives(%SpellData{effects: effects} = spell, radius_lookup) do
    case shapeshift_form_value(effects) do
      form when is_integer(form) ->
        passive_effects =
          form
          |> Scripts.shapeshift_passives()
          |> Enum.flat_map(&load_passive_aura_effects(&1, radius_lookup))
          |> Enum.with_index(length(effects))
          |> Enum.map(fn {effect, index} -> %{effect | index: index} end)

        %{spell | effects: effects ++ passive_effects}

      _ ->
        spell
    end
  end

  defp load_passive_aura_effects(passive_id, radius_lookup) do
    case DBC.get(Spell, passive_id) do
      nil -> []
      row -> passive_aura_effects(row, radius_lookup, 0)
    end
  end

  defp shapeshift_form_value(effects) do
    Enum.find_value(effects, fn
      %Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: misc} -> misc
      _ -> nil
    end)
  end

  defp passive_aura_effects(row, radius_lookup, index_offset) do
    row
    |> build_effects(radius_lookup)
    |> Enum.filter(&match?(%Effect{type: :apply_aura}, &1))
    |> Enum.with_index(index_offset)
    |> Enum.map(fn {effect, index} -> %{effect | index: index} end)
  end

  defp load_chain_map(spell_ids) do
    spell_ids
    |> Enum.map(&{&1, chain(&1)})
    |> Enum.reject(fn {_id, chain} -> is_nil(chain) end)
    |> Map.new()
  end

  defp put_chain(%SpellData{} = spell, %{first_spell: first_spell, rank: rank}) do
    %{spell | first_in_chain: first_spell, rank: rank}
  end

  defp put_chain(spell, _chain), do: spell

  defp build_reagents(row) do
    0..7
    |> Enum.map(fn index ->
      {Map.get(row, :"reagent_#{index}") || 0, Map.get(row, :"reagent_count_#{index}") || 0}
    end)
    |> Enum.filter(fn {item_id, count} -> item_id > 0 and count > 0 end)
  end

  defp build_effects(row, radius_lookup) do
    0..2
    |> Enum.map(&build_effect(row, &1, radius_lookup))
    |> Enum.reject(&is_nil/1)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp build_effect(row, index, radius_lookup) do
    type_int = Map.get(row, :"effect_#{index}") || 0

    case effect_type(row, type_int) do
      :none ->
        nil

      type ->
        aura = aura_type(Map.get(row, :"effect_aura_#{index}") || 0)

        %Effect{
          index: index,
          type: type,
          base_points: Map.get(row, :"effect_base_points_#{index}") || 0,
          die_sides: Map.get(row, :"effect_die_sides_#{index}") || 0,
          real_points_per_level: Map.get(row, :"effect_real_points_per_level_#{index}") || 0.0,
          points_per_combo: Map.get(row, :"effect_points_per_combo_#{index}") || 0.0,
          aura: aura,
          amplitude_ms: amplitude_ms(Map.get(row, :"effect_amplitude_#{index}")),
          misc_value: effect_misc_value(row, index, type, aura),
          multiple_value: Map.get(row, :"effect_multiple_values_#{index}") || 0.0,
          class_mask: unsigned32(Map.get(row, :"effect_item_type_#{index}")),
          item_type: unsigned32(Map.get(row, :"effect_item_type_#{index}")),
          radius_yards: radius_lookup.(Map.get(row, :"effect_radius_#{index}")),
          implicit_target_a: target_type(Map.get(row, :"implicit_target_a_#{index}") || 0),
          implicit_target_b: target_type(Map.get(row, :"implicit_target_b_#{index}") || 0),
          chain_targets: Map.get(row, :"effect_chain_target_#{index}") || 0,
          trigger_spell_id: nonzero(Map.get(row, :"effect_trigger_spell_#{index}")),
          summon_slot: summon_slot(type_int),
          damage_multiplier: damage_multiplier(Map.get(row, :"damage_multiplier_#{index}"))
        }
    end
  end

  defp effect_type(%Spell{spell_class_set: 10, spell_class_mask_0: mask}, 77)
       when is_integer(mask) and (mask &&& 0xC0000000) != 0, do: :heal

  defp effect_type(_row, type_int), do: effect_type(type_int)

  defp effect_misc_value(row, index, :create_item, _aura) do
    Map.get(row, :"effect_item_type_#{index}") || 0
  end

  defp effect_misc_value(row, index, _type, :transform) do
    transform_display_id(Map.get(row, :"effect_misc_value_#{index}") || 0)
  end

  defp effect_misc_value(row, index, _type, _aura) do
    Map.get(row, :"effect_misc_value_#{index}") || 0
  end

  defp transform_display_id(entry) when is_integer(entry) and entry > 0 do
    case CreatureTemplateLoader.get(entry) do
      %CreatureTemplate{display_ids: display_ids} when is_list(display_ids) ->
        Enum.find(display_ids, 0, &(is_integer(&1) and &1 > 0))

      _ ->
        0
    end
  end

  defp transform_display_id(_entry), do: 0

  defp load_radius_map(rows) do
    radius_ids =
      rows
      |> Enum.flat_map(fn row -> Enum.map(0..2, &Map.get(row, :"effect_radius_#{&1}")) end)
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.uniq()

    case radius_ids do
      [] ->
        %{}

      _ ->
        DBC.all(from(r in SpellRadius, where: r.id in ^radius_ids))
        |> Enum.reduce(%{}, fn
          %SpellRadius{id: id, radius: radius}, acc when is_number(radius) -> Map.put(acc, id, radius)
          _, acc -> acc
        end)
    end
  end

  defp lookup_radius(nil), do: nil
  defp lookup_radius(0), do: nil

  defp lookup_radius(radius_id) when is_integer(radius_id) do
    case DBC.get(SpellRadius, radius_id) do
      %SpellRadius{radius: radius} when is_number(radius) -> radius
      _ -> nil
    end
  end

  defp cast_time_ms(%SpellCastTimes{base: base}) when is_integer(base), do: base
  defp cast_time_ms(_), do: 0

  defp duration_ms(%SpellDuration{duration: duration}) when is_integer(duration), do: duration
  defp duration_ms(_), do: 0

  defp max_duration_ms(%SpellDuration{max_duration: duration}) when is_integer(duration), do: duration
  defp max_duration_ms(_), do: 0

  defp range_yards(%SpellRange{range_max: range}) when is_number(range), do: range
  defp range_yards(_), do: 0.0

  defp nonzero(value) when is_integer(value) and value > 0, do: value
  defp nonzero(_), do: nil

  defp damage_multiplier(value) when is_number(value) and value > 0, do: value
  defp damage_multiplier(_value), do: 1.0

  defp learned_spell_ids_from_row(row) do
    learned_ids =
      0..2
      |> Enum.filter(&(Map.get(row, :"effect_#{&1}") == @learn_spell_effect))
      |> Enum.map(&Map.get(row, :"effect_trigger_spell_#{&1}"))
      |> Enum.filter(&(is_integer(&1) and &1 > 0))

    case learned_ids do
      [] -> [row.id]
      ids -> ids
    end
  end

  defp school(0), do: :physical
  defp school(1), do: :holy
  defp school(2), do: :fire
  defp school(3), do: :nature
  defp school(4), do: :frost
  defp school(5), do: :shadow
  defp school(6), do: :arcane
  defp school(other) when is_integer(other), do: other

  defp effect_type(0), do: :none
  defp effect_type(1), do: :instakill
  defp effect_type(2), do: :school_damage
  defp effect_type(3), do: :dummy
  defp effect_type(5), do: :teleport_units
  defp effect_type(31), do: :weapon_percent_damage
  defp effect_type(121), do: :normalized_weapon_damage
  defp effect_type(104), do: :summon_game_object
  defp effect_type(6), do: :apply_aura
  defp effect_type(8), do: :power_drain
  defp effect_type(9), do: :health_leech
  defp effect_type(10), do: :heal
  defp effect_type(18), do: :resurrect
  defp effect_type(22), do: :parry
  defp effect_type(24), do: :create_item
  defp effect_type(25), do: :weapon
  defp effect_type(29), do: :leap
  defp effect_type(30), do: :energize
  defp effect_type(33), do: :open_lock
  defp effect_type(35), do: :apply_area_aura
  defp effect_type(36), do: :learn_spell
  defp effect_type(38), do: :dispel
  defp effect_type(40), do: :dual_wield
  defp effect_type(60), do: :proficiency
  defp effect_type(50), do: :trans_door
  defp effect_type(53), do: :enchant_item
  defp effect_type(54), do: :enchant_item_temporary
  defp effect_type(55), do: :tame_creature
  defp effect_type(56), do: :summon_pet
  defp effect_type(62), do: :power_burn
  defp effect_type(63), do: :modify_threat
  defp effect_type(68), do: :interrupt_cast
  defp effect_type(72), do: :add_farsight
  defp effect_type(73), do: :summon_possessed
  defp effect_type(77), do: :script_effect
  defp effect_type(79), do: :clear_threat
  defp effect_type(80), do: :add_combo_points
  defp effect_type(85), do: :summon_player
  defp effect_type(type) when type in 87..90, do: :summon_totem
  defp effect_type(96), do: :charge
  defp effect_type(101), do: :feed_pet
  defp effect_type(102), do: :dismiss_pet
  defp effect_type(109), do: :revive_pet
  defp effect_type(112), do: :summon_demon
  defp effect_type(92), do: :enchant_held_item
  defp effect_type(17), do: :weapon_damage_noschool
  defp effect_type(27), do: :persistent_area_aura
  defp effect_type(58), do: :weapon_damage
  defp effect_type(64), do: :trigger_spell
  defp effect_type(67), do: :heal_max_health
  defp effect_type(113), do: :resurrect_new
  defp effect_type(114), do: :attack_me
  defp effect_type(119), do: :apply_area_aura
  defp effect_type(other) when is_integer(other), do: other

  defp summon_slot(type) when type in 87..90, do: type - 86
  defp summon_slot(_type), do: nil

  defp aura_type(0), do: nil
  defp aura_type(1), do: :bind_sight
  defp aura_type(2), do: :mod_possess
  defp aura_type(3), do: :periodic_damage
  defp aura_type(4), do: :dummy
  defp aura_type(5), do: :mod_confuse
  defp aura_type(6), do: :mod_charm
  defp aura_type(7), do: :mod_fear
  defp aura_type(8), do: :periodic_heal
  defp aura_type(9), do: :mod_melee_haste
  defp aura_type(10), do: :mod_threat
  defp aura_type(11), do: :mod_taunt
  defp aura_type(12), do: :mod_stun
  defp aura_type(14), do: :mod_damage_taken
  defp aura_type(29), do: :mod_stat
  defp aura_type(30), do: :mod_skill
  defp aura_type(13), do: :mod_damage_done
  defp aura_type(15), do: :damage_shield
  defp aura_type(16), do: :mod_stealth
  defp aura_type(17), do: :mod_stealth_detect
  defp aura_type(22), do: :mod_resistance
  defp aura_type(23), do: :periodic_trigger_spell
  defp aura_type(24), do: :periodic_energize
  defp aura_type(25), do: :state_immunity
  defp aura_type(26), do: :mod_root
  defp aura_type(31), do: :mod_increase_speed
  defp aura_type(33), do: :mod_decrease_speed
  defp aura_type(34), do: :mod_increase_health
  defp aura_type(36), do: :mod_shapeshift
  defp aura_type(39), do: :school_immunity
  defp aura_type(41), do: :dispel_immunity
  defp aura_type(42), do: :proc_trigger_spell
  defp aura_type(43), do: :damage_shield
  defp aura_type(44), do: :track_creatures
  defp aura_type(47), do: :mod_parry_percent
  defp aura_type(49), do: :mod_dodge
  defp aura_type(51), do: :mod_block_percent
  defp aura_type(52), do: :mod_crit_percent
  defp aura_type(53), do: :periodic_leech
  defp aura_type(54), do: :mod_hit_chance
  defp aura_type(56), do: :transform
  defp aura_type(57), do: :mod_spell_crit_chance
  defp aura_type(58), do: :mod_increase_swim_speed
  defp aura_type(61), do: :mod_scale
  defp aura_type(64), do: :periodic_mana_leech
  defp aura_type(65), do: :mod_casting_speed
  defp aura_type(66), do: :feign_death
  defp aura_type(67), do: :mod_disarm
  defp aura_type(68), do: :mod_stalked
  defp aura_type(69), do: :school_absorb
  defp aura_type(71), do: :mod_spell_crit_chance_school
  defp aura_type(79), do: :mod_damage_percent_done
  defp aura_type(81), do: :split_damage_percent
  defp aura_type(82), do: :water_breathing
  defp aura_type(87), do: :mod_damage_percent_taken
  defp aura_type(74), do: :reflect_spells_school
  defp aura_type(77), do: :mechanic_immunity
  defp aura_type(84), do: :mod_regen
  defp aura_type(85), do: :mod_power_regen
  defp aura_type(86), do: :channel_death_item
  defp aura_type(88), do: :mod_health_regen_percent
  defp aura_type(91), do: :mod_detect_range
  defp aura_type(92), do: :prevent_fleeing
  defp aura_type(94), do: :interrupt_regen
  defp aura_type(95), do: :ghost
  defp aura_type(97), do: :mana_shield
  defp aura_type(99), do: :mod_attack_power
  defp aura_type(101), do: :mod_resistance_percent
  defp aura_type(103), do: :mod_total_threat
  defp aura_type(104), do: :water_walk
  defp aura_type(105), do: :feather_fall
  defp aura_type(106), do: :hover
  defp aura_type(107), do: :add_flat_modifier
  defp aura_type(108), do: :add_pct_modifier
  defp aura_type(110), do: :mod_power_regen_percent
  defp aura_type(113), do: :mod_ranged_damage_taken
  defp aura_type(115), do: :mod_healing
  defp aura_type(116), do: :mod_regen_during_combat
  defp aura_type(117), do: :mechanic_resistance
  defp aura_type(118), do: :mod_healing_pct
  defp aura_type(120), do: :untrackable
  defp aura_type(121), do: :empathy
  defp aura_type(124), do: :mod_ranged_attack_power
  defp aura_type(127), do: :ranged_attack_power_attacker_bonus
  defp aura_type(128), do: :mod_possess_pet
  defp aura_type(134), do: :mod_mana_regen_interrupt
  defp aura_type(135), do: :mod_healing_done
  defp aura_type(137), do: :mod_total_stat_percent
  defp aura_type(138), do: :mod_melee_haste
  defp aura_type(140), do: :mod_ranged_haste
  defp aura_type(141), do: :mod_ranged_haste
  defp aura_type(142), do: :mod_base_resistance_percent
  defp aura_type(143), do: :mod_resistance_exclusive
  defp aura_type(144), do: :safe_fall
  defp aura_type(149), do: :reduce_pushback
  defp aura_type(151), do: :track_stealthed
  defp aura_type(153), do: :split_damage_flat
  defp aura_type(161), do: :mod_health_regen_in_combat
  defp aura_type(other) when is_integer(other), do: other

  defp target_type(0), do: nil
  defp target_type(1), do: :caster
  defp target_type(6), do: :target_enemy
  defp target_type(21), do: :target_ally
  defp target_type(57), do: :target_ally
  defp target_type(15), do: :aoe_enemy_at_caster
  defp target_type(16), do: :aoe_enemy_at_dest
  defp target_type(18), do: :caster_destination
  defp target_type(20), do: :party_around_caster
  defp target_type(22), do: :aoe_enemy_at_caster
  defp target_type(33), do: :party_around_caster
  defp target_type(34), do: :party_around_caster
  defp target_type(39), do: :caster_fishing_spot
  defp target_type(24), do: :aoe_enemy_in_cone
  defp target_type(28), do: :aoe_enemy_at_channel
  defp target_type(32), do: :minion_position
  defp target_type(5), do: :pet
  defp target_type(53), do: :aoe_enemy_at_dest
  defp target_type(other) when is_integer(other), do: other

  @on_next_swing_1 0x00000004
  @on_next_swing_2 0x00000400
  @passive 0x00000040
  @ability 0x00000010
  @hidden_in_combat_log 0x00000100
  @not_in_combat 0x10000000
  @aura_is_debuff 0x04000000
  @cant_cancel 0x80000000
  @cooldown_on_event 0x02000000
  @channeled_ex_1 0x00000004
  @channeled_ex_2 0x00000040
  @discount_power_on_miss_ex_1 0x08000000
  @finishing_move_damage_ex_1 0x00100000
  @finishing_move_duration_ex_1 0x00400000
  @ignore_line_of_sight_ex2 0x00000004
  @cant_crit_ex2 0x20000000
  @from_behind_ex2 0x00100000
  @from_behind_ex1 0x00000200
  @completely_blocked_ex3 0x00000008

  defp attributes(attrs, attrs_ex1, attrs_ex2, attrs_ex3) when is_integer(attrs) and is_integer(attrs_ex1) do
    attrs_ex2 = if is_integer(attrs_ex2), do: attrs_ex2, else: 0
    attrs_ex3 = if is_integer(attrs_ex3), do: attrs_ex3, else: 0

    base =
      MapSet.new()
      |> add_if(attrs, @on_next_swing_1, :on_next_swing)
      |> add_if(attrs, @on_next_swing_2, :on_next_swing)
      |> add_if(attrs, @passive, :passive)
      |> add_if(attrs, @ability, :ability)
      |> add_if(attrs, @hidden_in_combat_log, :hidden_in_combat_log)
      |> add_if(attrs, @not_in_combat, :not_in_combat)
      |> add_if(attrs, @aura_is_debuff, :negative)
      |> add_if(attrs, @cant_cancel, :cant_cancel)
      |> add_if(attrs, @cooldown_on_event, :cooldown_on_event)

    base = if attrs == 0x150010, do: MapSet.put(base, :target_facing_caster), else: base
    base = if from_behind?(attrs_ex1, attrs_ex2), do: MapSet.put(base, :from_behind), else: base

    base
    |> add_if(attrs_ex1, @channeled_ex_1, :channeled)
    |> add_if(attrs_ex1, @channeled_ex_2, :channeled)
    |> add_if(attrs_ex1, @discount_power_on_miss_ex_1, :discount_power_on_miss)
    |> add_if(attrs_ex1, @finishing_move_damage_ex_1, :finishing_move)
    |> add_if(attrs_ex1, @finishing_move_duration_ex_1, :finishing_move)
    |> add_if(attrs_ex2, @ignore_line_of_sight_ex2, :ignore_line_of_sight)
    |> add_if(attrs_ex2, @cant_crit_ex2, :cant_crit)
    |> add_if(attrs_ex3, @completely_blocked_ex3, :completely_blocked)
  end

  defp attributes(_, _, _, _), do: MapSet.new()

  defp from_behind?(attrs_ex1, attrs_ex2) do
    attrs_ex2 == @from_behind_ex2 and (attrs_ex1 &&& @from_behind_ex1) != 0
  end

  defp add_if(set, mask, bit, atom) do
    if (mask &&& bit) == 0, do: set, else: MapSet.put(set, atom)
  end

  defp amplitude_ms(value) when is_float(value) do
    <<int::little-signed-32>> = <<value::little-float-32>>
    max(int, 0)
  rescue
    _ -> 0
  end

  defp amplitude_ms(value) when is_integer(value), do: max(value, 0)
  defp amplitude_ms(_), do: 0
end
