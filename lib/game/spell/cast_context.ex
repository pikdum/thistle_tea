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
    :caster_position,
    :target_guid,
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
    :caster_power,
    :combo_points,
    :spell_threat,
    spell_damage_bonus: %{},
    healing_bonus: 0,
    threat_multiplier: 1.0,
    damage_done_multiplier: 1.0,
    melee_crit?: false
  ]

  def from_caster(%{object: %{guid: guid}, unit: %{level: level}} = caster, spell, target_guid)
      when is_integer(guid) and is_integer(level) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: level,
      caster_type: caster_type(caster),
      caster_position: caster_position(caster),
      target_guid: target_guid,
      spell: spell,
      spell_damage_bonus: spell_damage_bonus(caster),
      healing_bonus: healing_bonus(caster),
      spell_threat: SpellThreatLoader.get(spell_id(spell)),
      threat_multiplier: Aura.percent_multiplier(caster, :mod_threat, Spell.school_mask(spell)),
      damage_done_multiplier: Aura.percent_multiplier(caster, :mod_damage_percent_done, Spell.school_mask(spell))
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
  end

  def from_caster(%{object: %{guid: guid}} = caster, spell, target_guid) when is_integer(guid) do
    %__MODULE__{
      caster_guid: guid,
      caster_level: 1,
      caster_type: caster_type(caster),
      caster_position: caster_position(caster),
      target_guid: target_guid,
      spell: spell
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
  end

  defp caster_type(%Character{}), do: :player
  defp caster_type(%Mob{}), do: :mob
  defp caster_type(_), do: nil

  defp spell_id(%Spell{id: id}), do: id
  defp spell_id(_spell), do: nil

  defp caster_position(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}) do
    {world, x, y, z}
  end

  defp caster_position(_caster), do: nil

  defp put_melee_snapshot(%__MODULE__{} = context, caster, %Spell{} = spell) do
    cond do
      Spell.ranged_ability?(spell) ->
        %{
          context
          | attack_power: caster.unit.ranged_attack_power || 0,
            weapon_base_min: caster.unit.base_ranged_min_damage || caster.unit.min_ranged_damage || 0,
            weapon_base_max: caster.unit.base_ranged_max_damage || caster.unit.max_ranged_damage || 0,
            attack_time_ms: caster.unit.ranged_attack_time,
            attack_skill: ranged_attack_skill(caster),
            melee_crit_chance: ranged_crit_chance(caster)
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
            melee_crit_chance: melee_crit_chance(caster),
            caster_power: caster_power(caster)
        }

      true ->
        context
    end
  end

  defp put_melee_snapshot(context, _caster, _spell), do: context

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

  defp melee_crit_chance(%Character{unit: unit} = caster) do
    if Aura.auras_of_type(caster, :force_crit) == [] do
      CombatRatings.melee_crit_chance(unit.class, unit.level || 1, unit.agility || 0) +
        Aura.flat_amount(caster, :mod_crit_percent)
    else
      100.0
    end
  end

  defp melee_crit_chance(_caster), do: nil

  defp caster_power(%{unit: %{power_type: 1, power2: rage}}) when is_integer(rage), do: rage
  defp caster_power(%{unit: %{power_type: 3, power4: energy}}) when is_integer(energy), do: energy
  defp caster_power(_caster), do: nil

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

  defp ranged_crit_chance(%Character{player: player, unit: unit}) when is_struct(player) do
    player.ranged_crit_percentage || CombatRatings.melee_crit_chance(unit.class, unit.level || 1, unit.agility || 0)
  end

  defp ranged_crit_chance(_caster), do: nil

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
