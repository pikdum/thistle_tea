defmodule ThistleTea.Game.Spell.CastContext do
  @moduledoc """
  Snapshot of the caster taken at cast time — guid, level, spell
  damage/healing bonuses, and for melee abilities the weapon/attack-power
  numbers — so effects apply consistently even after the caster's state
  changes.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.SpellThreat, as: SpellThreatLoader

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @two_hand_inventory_type 17
  @dagger_subclass 15
  @weapon_item_class 2

  @normalized_two_hand 3.3
  @normalized_dagger 1.7
  @normalized_one_hand 2.4
  @normalized_unarmed 2.0

  defstruct [
    :caster_guid,
    :caster_level,
    :caster_type,
    :caster_faction_template,
    :caster_position,
    :caster_orientation,
    :destination_position,
    :caster_zone,
    :target_guid,
    :selected_target_guid,
    :target_role,
    :target_hostile?,
    :spell,
    :attack_power,
    :weapon_base_min,
    :weapon_base_max,
    :attack_time_ms,
    :normalized_speed,
    :attack_skill,
    :melee_crit_chance,
    :hit_chance_bonus,
    :spell_crit_chance,
    :shield_block_value,
    :caster_power,
    :combo_points,
    :spell_threat,
    spell_modifiers: [],
    spell_damage_bonus: %{},
    healing_bonus: 0,
    threat_multiplier: 1.0,
    damage_done_multiplier: 1.0,
    effect_damage_multiplier: 1.0,
    effect_healing_multiplier: 1.0,
    melee_crit?: false
  ]

  def from_caster(%{object: %{guid: guid}, unit: %{level: level}} = caster, spell, target_guid)
      when is_integer(guid) and is_integer(level) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: level,
      caster_type: caster_type(caster),
      caster_faction_template: caster_faction_template(caster),
      caster_position: caster_position(caster),
      caster_orientation: caster_orientation(caster),
      target_guid: target_guid,
      spell: spell,
      spell_damage_bonus: spell_damage_bonus(caster),
      healing_bonus: healing_bonus(caster),
      spell_threat: SpellThreatLoader.get(spell_id(spell)),
      spell_modifiers: Modifiers.snapshot(caster, spell),
      threat_multiplier: Aura.percent_multiplier(caster, :mod_threat, Spell.school_mask(spell)),
      damage_done_multiplier: Aura.percent_multiplier(caster, :mod_damage_percent_done, Spell.school_mask(spell)),
      effect_damage_multiplier: effect_multiplier(caster, spell, [:all_effects, :damage]),
      effect_healing_multiplier: effect_multiplier(caster, spell, [:all_effects]),
      spell_crit_chance: spell_crit_chance(caster, spell),
      hit_chance_bonus: Aura.flat_amount(caster, :mod_hit_chance)
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
  end

  def from_caster(%{object: %{guid: guid}} = caster, spell, target_guid) when is_integer(guid) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: 1,
      caster_type: caster_type(caster),
      caster_faction_template: caster_faction_template(caster),
      caster_position: caster_position(caster),
      caster_orientation: caster_orientation(caster),
      target_guid: target_guid,
      spell: spell,
      hit_chance_bonus: Aura.flat_amount(caster, :mod_hit_chance)
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
  end

  defp caster_type(%Character{}), do: :player
  defp caster_type(%Mob{}), do: :mob
  defp caster_type(_), do: nil

  defp caster_faction_template(%{unit: %{faction_template: faction_template}}), do: faction_template
  defp caster_faction_template(_caster), do: nil

  defp spell_id(%Spell{id: id}), do: id
  defp spell_id(_spell), do: nil

  defp caster_position(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}) do
    {world, x, y, z}
  end

  defp caster_position(_caster), do: nil

  defp caster_orientation(%{movement_block: %{position: {_x, _y, _z, orientation}}}), do: orientation
  defp caster_orientation(_caster), do: nil

  defp put_melee_snapshot(%__MODULE__{} = context, caster, %Spell{} = spell) do
    if Scripts.uses_melee_spell_crit?(spell) do
      %{context | spell_crit_chance: melee_crit_chance(caster, spell)}
    else
      put_attack_snapshot(context, caster, spell)
    end
  end

  defp put_melee_snapshot(context, _caster, _spell), do: context

  defp put_attack_snapshot(%__MODULE__{} = context, caster, %Spell{} = spell) do
    cond do
      Spell.ranged_ability?(spell) ->
        %{
          context
          | attack_power: caster.unit.ranged_attack_power || 0,
            weapon_base_min: caster.unit.base_ranged_min_damage || caster.unit.min_ranged_damage || 0,
            weapon_base_max: caster.unit.base_ranged_max_damage || caster.unit.max_ranged_damage || 0,
            attack_time_ms: caster.unit.ranged_attack_time,
            attack_skill: ranged_attack_skill(caster),
            melee_crit_chance: ranged_crit_chance(caster, spell),
            spell_crit_chance: ranged_crit_chance(caster, spell)
        }

      melee_snapshot?(spell) ->
        %{
          context
          | attack_power: melee_attack_power(caster),
            weapon_base_min: weapon_base(caster, :base_min_damage, :min_damage),
            weapon_base_max: weapon_base(caster, :base_max_damage, :max_damage),
            attack_time_ms: caster.unit.base_attack_time,
            normalized_speed: normalized_speed(caster),
            attack_skill: attack_skill(caster),
            melee_crit_chance: melee_crit_chance(caster, spell),
            shield_block_value: shield_block_value(caster),
            caster_power: caster_power(caster)
        }

      true ->
        context
    end
  end

  defp put_combo_points(%__MODULE__{} = context, %Character{player: player}) do
    %{context | combo_points: max(player.combo_points || 0, 0)}
  end

  defp put_combo_points(context, _caster), do: context

  defp melee_snapshot?(%Spell{effects: effects} = spell) do
    Spell.melee_ability?(spell) or
      Enum.any?(effects, &(&1.type in Spell.weapon_damage_effect_types()))
  end

  defp melee_attack_power(%{unit: %{base_min_damage: base, attack_power: attack_power}})
       when is_number(base) and is_integer(attack_power) do
    attack_power
  end

  defp melee_attack_power(_caster), do: 0

  defp weapon_base(%{unit: unit}, base_field, current_field) do
    case Map.get(unit, base_field) do
      base when is_number(base) -> base
      _ -> Map.get(unit, current_field) || 0
    end
  end

  defp normalized_speed(%Character{} = caster) do
    case main_hand_template(caster) do
      %{inventory_type: @two_hand_inventory_type} -> @normalized_two_hand
      %{subclass: @dagger_subclass} -> @normalized_dagger
      %{class: @weapon_item_class} -> @normalized_one_hand
      _ -> @normalized_unarmed
    end
  end

  defp normalized_speed(_caster), do: @normalized_unarmed

  defp attack_skill(%Character{unit: unit, player: player}) when is_struct(player) do
    skill_id = Skills.main_hand_weapon_skill(player, &ItemLoader.get_template/1)
    Skills.value(player.skills, skill_id, Skills.max_for_level(unit.level || 1))
  end

  defp attack_skill(_caster), do: nil

  defp melee_crit_chance(%Character{unit: unit} = caster, %Spell{} = spell) do
    base =
      CombatRatings.melee_crit_chance(unit.class, unit.level || 1, unit.agility || 0) +
        Aura.flat_amount(caster, :mod_crit_percent)

    Modifiers.value(caster, spell, :critical_chance, base)
  end

  defp melee_crit_chance(_caster, _spell), do: nil

  defp caster_power(%{unit: %{power_type: 1, power2: rage}}) when is_integer(rage), do: rage
  defp caster_power(%{unit: %{power_type: 3, power4: energy}}) when is_integer(energy), do: energy
  defp caster_power(_caster), do: nil

  defp shield_block_value(%{unit: unit}) do
    CombatRatings.block_value(unit.equipment_bonuses || %{}, unit.strength || 0)
  end

  defp main_hand_template(%Character{player: player}) when is_struct(player) do
    case player.visible_item_16_0 do
      entry when is_integer(entry) and entry > 0 -> ItemLoader.get_template(entry)
      _ -> nil
    end
  end

  defp main_hand_template(_caster), do: nil

  defp ranged_attack_skill(%Character{unit: unit, player: player}) when is_struct(player) do
    skill_id = Skills.ranged_weapon_skill(player, &ItemLoader.get_template/1)
    Skills.value(player.skills, skill_id, Skills.max_for_level(unit.level || 1))
  end

  defp ranged_attack_skill(_caster), do: nil

  defp ranged_crit_chance(%Character{player: player, unit: unit} = caster, %Spell{} = spell) when is_struct(player) do
    base =
      player.ranged_crit_percentage || CombatRatings.melee_crit_chance(unit.class, unit.level || 1, unit.agility || 0)

    Modifiers.value(caster, spell, :critical_chance, base)
  end

  defp ranged_crit_chance(_caster, _spell), do: nil

  defp spell_crit_chance(%Character{unit: unit} = caster, %Spell{} = spell) do
    base = CombatRatings.spell_crit_chance(unit.class, unit.level || 1, unit.intellect || 0)

    chance =
      base +
        Aura.flat_amount(caster, :mod_spell_crit_chance) +
        Aura.flat_modifier(caster, :mod_spell_crit_chance_school, Spell.school_mask(spell))

    Modifiers.value(caster, spell, :critical_chance, chance)
  end

  defp spell_crit_chance(_caster, _spell), do: 0.0

  defp effect_multiplier(caster, %Spell{} = spell, operations) do
    Enum.reduce(operations, 1.0, fn operation, multiplier ->
      multiplier * Modifiers.value(caster, spell, operation, 100) / 100
    end)
  end

  defp spell_damage_bonus(caster) do
    bonuses = equipment_bonuses(caster)
    Map.new(@schools, fn school -> {school, Map.get(bonuses, :"spell_#{school}", 0)} end)
  end

  defp healing_bonus(caster) do
    caster |> equipment_bonuses() |> Map.get(:healing, 0)
  end

  defp equipment_bonuses(%{unit: %{equipment_bonuses: %{} = bonuses}}), do: bonuses
  defp equipment_bonuses(_caster), do: %{}
end
