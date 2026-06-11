defmodule ThistleTea.Game.World.Loader.Spell do
  import Bitwise, only: [&&&: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.Spell.Effect

  @learn_spell_effect 36

  def load(spell_id) when is_integer(spell_id) and spell_id > 0 do
    case DBC.get(Spell, spell_id) do
      nil -> nil
      row -> build(row)
    end
  end

  def load(_), do: nil

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

    rows
    |> Enum.map(&build_preloaded(&1, radius_lookup))
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

  defp build(row) do
    row = DBC.preload(row, [:spell_cast_time, :spell_duration, :spell_range])
    build_preloaded(row, &lookup_radius/1)
  end

  defp build_preloaded(row, radius_lookup) do
    %SpellData{
      id: row.id,
      name: row.name_en_gb,
      school: school(row.school),
      cast_time_ms: cast_time_ms(row.spell_cast_time),
      duration_ms: duration_ms(row.spell_duration),
      range_yards: range_yards(row.spell_range),
      mana_cost: row.mana_cost || 0,
      gcd_ms: row.start_recovery_time || 0,
      dispel_type: row.dispel_type || 0,
      speed: row.speed || 0.0,
      aura_interrupt_flags: row.aura_interrupt_flags || 0,
      attributes: attributes(row.attributes, row.attributes_ex1),
      effects: build_effects(row, radius_lookup),
      reagents: build_reagents(row)
    }
  end

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

  defp build_effect(row, index, radius_lookup) do
    type_int = Map.get(row, :"effect_#{index}") || 0

    case effect_type(type_int) do
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
          aura: aura,
          amplitude_ms: amplitude_ms(Map.get(row, :"effect_amplitude_#{index}")),
          misc_value: effect_misc_value(row, index, type, aura),
          radius_yards: radius_lookup.(Map.get(row, :"effect_radius_#{index}")),
          implicit_target_a: target_type(Map.get(row, :"implicit_target_a_#{index}") || 0),
          implicit_target_b: target_type(Map.get(row, :"implicit_target_b_#{index}") || 0),
          chain_targets: Map.get(row, :"effect_chain_target_#{index}") || 0,
          trigger_spell_id: nonzero(Map.get(row, :"effect_trigger_spell_#{index}"))
        }
    end
  end

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
    case Mangos.Repo.get(Mangos.CreatureTemplate, entry) do
      %Mangos.CreatureTemplate{} = template ->
        [template.model_id1, template.model_id2, template.model_id3, template.model_id4]
        |> Enum.find(0, &(is_integer(&1) and &1 > 0))

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

  defp range_yards(%SpellRange{range_max: range}) when is_number(range), do: range
  defp range_yards(_), do: 0.0

  defp nonzero(value) when is_integer(value) and value > 0, do: value
  defp nonzero(_), do: nil

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
  defp effect_type(2), do: :school_damage
  defp effect_type(5), do: :teleport_units
  defp effect_type(6), do: :apply_aura
  defp effect_type(10), do: :heal
  defp effect_type(24), do: :create_item
  defp effect_type(29), do: :leap
  defp effect_type(38), do: :dispel
  defp effect_type(50), do: :trans_door
  defp effect_type(68), do: :interrupt_cast
  defp effect_type(17), do: :weapon_damage_noschool
  defp effect_type(27), do: :persistent_area_aura
  defp effect_type(58), do: :weapon_damage
  defp effect_type(64), do: :trigger_spell
  defp effect_type(other) when is_integer(other), do: other

  defp aura_type(0), do: nil
  defp aura_type(3), do: :periodic_damage
  defp aura_type(4), do: :dummy
  defp aura_type(5), do: :mod_confuse
  defp aura_type(8), do: :periodic_heal
  defp aura_type(12), do: :mod_stun
  defp aura_type(14), do: :mod_damage_taken
  defp aura_type(29), do: :mod_stat
  defp aura_type(13), do: :mod_damage_done
  defp aura_type(15), do: :damage_shield
  defp aura_type(22), do: :mod_resistance
  defp aura_type(23), do: :periodic_trigger_spell
  defp aura_type(26), do: :mod_root
  defp aura_type(31), do: :mod_increase_speed
  defp aura_type(33), do: :mod_decrease_speed
  defp aura_type(42), do: :proc_trigger_spell
  defp aura_type(56), do: :transform
  defp aura_type(58), do: :mod_increase_swim_speed
  defp aura_type(69), do: :school_absorb
  defp aura_type(74), do: :reflect_spells_school
  defp aura_type(77), do: :mechanic_immunity
  defp aura_type(84), do: :mod_regen
  defp aura_type(85), do: :mod_power_regen
  defp aura_type(95), do: :ghost
  defp aura_type(97), do: :mana_shield
  defp aura_type(99), do: :mod_attack_power
  defp aura_type(105), do: :feather_fall
  defp aura_type(110), do: :mod_power_regen_percent
  defp aura_type(115), do: :mod_healing
  defp aura_type(134), do: :mod_mana_regen_interrupt
  defp aura_type(135), do: :mod_healing_done
  defp aura_type(other) when is_integer(other), do: other

  defp target_type(0), do: nil
  defp target_type(1), do: :caster
  defp target_type(6), do: :target_enemy
  defp target_type(15), do: :aoe_enemy_at_caster
  defp target_type(22), do: :aoe_enemy_at_caster
  defp target_type(24), do: :aoe_enemy_in_cone
  defp target_type(28), do: :aoe_enemy_at_channel
  defp target_type(53), do: :aoe_enemy_at_dest
  defp target_type(other) when is_integer(other), do: other

  @on_next_swing_1 0x00000004
  @on_next_swing_2 0x00000400
  @passive 0x00000040
  @ability 0x00000010
  @hidden_in_combat_log 0x00000100
  @channeled_ex_1 0x00000004
  @channeled_ex_2 0x00000040

  defp attributes(attrs, attrs_ex1) when is_integer(attrs) and is_integer(attrs_ex1) do
    base =
      MapSet.new()
      |> add_if(attrs, @on_next_swing_1, :on_next_swing)
      |> add_if(attrs, @on_next_swing_2, :on_next_swing)
      |> add_if(attrs, @passive, :passive)
      |> add_if(attrs, @ability, :ability)
      |> add_if(attrs, @hidden_in_combat_log, :hidden_in_combat_log)

    base
    |> add_if(attrs_ex1, @channeled_ex_1, :channeled)
    |> add_if(attrs_ex1, @channeled_ex_2, :channeled)
  end

  defp attributes(_, _), do: MapSet.new()

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
