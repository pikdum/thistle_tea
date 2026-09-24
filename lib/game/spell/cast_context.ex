defmodule ThistleTea.Game.Spell.CastContext do
  @moduledoc """
  Snapshot of the caster taken at cast time — guid, level, spell
  damage/healing bonuses, and for melee abilities the weapon/attack-power
  numbers — so effects apply consistently even after the caster's state
  changes. The receiving owner refreshes threat modifiers when the spell lands
  and caster availability for periodic life drains.
  """
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackPower
  alias ThistleTea.Game.Entity.Logic.AttackSpeed
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Mage
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Entity.Logic.TargetAttackPower
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Entity.Logic.TargetSpellPower
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Critical
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.SpellThreat, as: SpellThreatLoader

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @two_hand_inventory_type 17
  @dagger_subclass 15
  @weapon_item_class 2

  @normalized_two_hand 3.3
  @normalized_dagger 1.7
  @normalized_one_hand 2.4
  @normalized_unarmed 2.0
  @normalized_ranged 2.8

  defstruct [
    :cast_item_guid,
    :cooldown_started_at,
    :caster_guid,
    :caster_owner_guid,
    :reflected_by_guid,
    :caster_level,
    :caster_type,
    :caster_faction_template,
    :caster_position,
    :caster_bounding_radius,
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
    :weapon_skill_id,
    :melee_crit_chance,
    :hit_chance_bonus,
    :spell_crit_chance,
    :reflect_chance_bonus,
    :shield_block_value,
    :caster_power,
    :caster_max_health,
    :combo_points,
    :combo_retention_spell,
    :spell_threat,
    :spell_hit_snapshot,
    :chain_effects,
    triggered_by_aura?: false,
    caster_available?: true,
    caster_totem?: false,
    triggered?: false,
    proc_damage?: false,
    extra_attack?: false,
    hit_outcome: :hit,
    spell_hit_bonus: 0,
    dispel_resistance: %{},
    spell_modifiers: [],
    conditional_crit_modifiers: [],
    damage_done_versus: [],
    target_attack_power: %{},
    target_damage: [],
    crit_damage_versus: [],
    spell_damage_bonus: %{},
    spell_damage_versus: [],
    healing_bonus: 0,
    resistance_penetration: [],
    threat_multiplier: 1.0,
    critical_threat_multiplier: 1.0,
    healing_threat_ratio: 0.5,
    damage_done_multiplier: 1.0,
    happiness_multiplier: 1.0,
    effect_damage_multiplier: 1.0,
    weapon_attack_power_included?: false,
    effect_healing_multiplier: 1.0,
    melee_crit?: false
  ]

  def from_caster(%{object: %{guid: guid}, unit: %{level: level}} = caster, spell, target_guid)
      when is_integer(guid) and is_integer(level) do
    spell = WeaponDamage.prepare_spell(caster, spell)
    hit_snapshot = SpellResist.hit_snapshot(caster)

    %__MODULE__{
      caster_guid: guid,
      caster_owner_guid: caster_owner_guid(caster),
      caster_level: level,
      caster_type: caster_type(caster),
      caster_totem?: caster_totem?(caster),
      caster_faction_template: caster_faction_template(caster),
      caster_position: caster_position(caster),
      caster_bounding_radius: caster_bounding_radius(caster),
      caster_orientation: caster_orientation(caster),
      target_guid: target_guid,
      spell: spell,
      spell_damage_bonus: spell_damage_bonus(caster),
      spell_damage_versus: TargetSpellPower.snapshot(caster),
      healing_bonus: healing_bonus(caster, spell),
      resistance_penetration: ResistancePenetration.snapshot(caster),
      spell_threat: SpellThreatLoader.get(spell_id(spell)),
      spell_modifiers: Modifiers.snapshot(caster, spell),
      spell_hit_snapshot: hit_snapshot,
      spell_hit_bonus: SpellResist.hit_bonus(hit_snapshot, spell),
      conditional_crit_modifiers: Critical.snapshot(caster, spell),
      damage_done_multiplier: WeaponDamage.multiplier(caster, spell.school, attack_weapon(caster, spell)),
      happiness_multiplier: PetHappiness.damage_multiplier(caster),
      damage_done_versus: Aura.misc_amounts(caster, :mod_damage_done_versus),
      target_attack_power: TargetAttackPower.snapshot(caster),
      target_damage: TargetDamage.snapshot(caster),
      crit_damage_versus: Aura.misc_amounts(caster, :mod_crit_percent_versus),
      effect_damage_multiplier: effect_multiplier(caster, spell, [:all_effects, :damage]),
      effect_healing_multiplier: healing_done_multiplier(caster, spell),
      spell_crit_chance: spell_crit_chance(caster, spell),
      reflect_chance_bonus: Mage.ward_reflect_chance(caster, spell),
      caster_max_health: caster.unit.max_health,
      hit_chance_bonus: CombatRatings.hit_chance(caster, attack_hand(spell))
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
    |> SpellThreat.put_context(spell, SpellThreat.projection(caster))
  end

  def from_caster(%{object: %{guid: guid}} = caster, spell, target_guid) when is_integer(guid) do
    %__MODULE__{
      caster_guid: guid,
      caster_owner_guid: caster_owner_guid(caster),
      caster_level: 1,
      caster_type: caster_type(caster),
      caster_totem?: caster_totem?(caster),
      caster_faction_template: caster_faction_template(caster),
      caster_position: caster_position(caster),
      caster_bounding_radius: caster_bounding_radius(caster),
      caster_orientation: caster_orientation(caster),
      target_guid: target_guid,
      spell: spell,
      conditional_crit_modifiers: Critical.snapshot(caster, spell),
      reflect_chance_bonus: Mage.ward_reflect_chance(caster, spell),
      hit_chance_bonus: CombatRatings.hit_chance(caster, attack_hand(spell))
    }
    |> put_melee_snapshot(caster, spell)
    |> put_combo_points(caster)
    |> SpellThreat.put_context(spell, SpellThreat.projection(caster))
  end

  defp caster_type(%Character{}), do: :player
  defp caster_type(%Mob{}), do: :mob
  defp caster_type(_), do: nil

  defp caster_totem?(%{internal: %{totem: totem}}), do: not is_nil(totem)
  defp caster_totem?(_caster), do: false

  defp caster_owner_guid(%{internal: %{pet: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp caster_owner_guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid

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

  defp caster_bounding_radius(%{unit: %Unit{bounding_radius: radius}}), do: radius || Unit.default_bounding_radius()
  defp caster_bounding_radius(_caster), do: 0.0

  defp put_melee_snapshot(%__MODULE__{} = context, caster, %Spell{} = spell) do
    if Semantics.rules(spell).melee_spell_crit? do
      %{context | spell_crit_chance: melee_crit_chance(caster, spell)}
    else
      put_attack_snapshot(context, caster, spell)
    end
  end

  defp put_melee_snapshot(context, _caster, _spell), do: context

  defp put_attack_snapshot(%__MODULE__{} = context, caster, %Spell{} = spell) do
    cond do
      Spell.ranged_attack?(spell) ->
        {min_damage, max_damage} = AttackPower.weapon_range(caster.unit, :ranged)
        skill = CombatSkills.snapshot(caster, :ranged)

        %{
          context
          | attack_power: WeaponDamage.ranged_attack_power(caster.unit),
            weapon_attack_power_included?: AttackPower.creature?(caster.unit),
            weapon_base_min: min_damage,
            weapon_base_max: max_damage,
            attack_time_ms: AttackSpeed.base_ms(caster.unit, :ranged),
            normalized_speed: @normalized_ranged,
            attack_skill: skill.caster_attack_skill,
            weapon_skill_id: skill.weapon_skill_id,
            melee_crit_chance: ranged_crit_chance(caster, spell),
            spell_crit_chance: ranged_crit_chance(caster, spell)
        }

      melee_snapshot?(spell) ->
        {min_damage, max_damage} = weapon_range(caster)
        skill = CombatSkills.snapshot(caster, :mainhand)

        %{
          context
          | attack_power: melee_attack_power(caster),
            weapon_attack_power_included?: AttackPower.creature?(caster.unit),
            weapon_base_min: min_damage,
            weapon_base_max: max_damage,
            attack_time_ms: AttackSpeed.base_ms(caster.unit, :mainhand),
            normalized_speed: normalized_speed(caster),
            attack_skill: skill.caster_attack_skill,
            weapon_skill_id: skill.weapon_skill_id,
            melee_crit_chance: melee_crit_chance(caster, spell),
            shield_block_value: CombatRatings.block_value(caster),
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

  defp weapon_range(%{unit: unit} = caster) do
    if match?(%Character{}, caster) and Disarm.unarmed?(caster) do
      {1.0, 2.0}
    else
      AttackPower.weapon_range(unit, :melee)
    end
  end

  defp normalized_speed(%Character{} = caster) do
    weapon = CombatWeapon.usable(caster, :mainhand)

    case weapon do
      %{inventory_type: @two_hand_inventory_type} -> @normalized_two_hand
      %{subclass: @dagger_subclass} -> @normalized_dagger
      %{class: @weapon_item_class} -> @normalized_one_hand
      _ -> @normalized_unarmed
    end
  end

  defp normalized_speed(_caster), do: @normalized_unarmed

  defp melee_crit_chance(%Character{} = caster, %Spell{} = spell) do
    Modifiers.value(caster, spell, :critical_chance, CombatRatings.crit_chance(caster, :mainhand))
  end

  defp melee_crit_chance(_caster, _spell), do: nil

  defp caster_power(%{unit: %{power_type: 1, power2: rage}}) when is_integer(rage), do: rage
  defp caster_power(%{unit: %{power_type: 3, power4: energy}}) when is_integer(energy), do: energy
  defp caster_power(_caster), do: nil

  defp attack_weapon(caster, %Spell{} = spell) do
    cond do
      Spell.ranged_attack?(spell) -> CombatWeapon.usable(caster, :ranged)
      melee_snapshot?(spell) -> CombatWeapon.usable(caster, :mainhand)
      true -> nil
    end
  end

  defp attack_hand(%Spell{} = spell), do: if(Spell.ranged_attack?(spell), do: :ranged, else: :mainhand)
  defp attack_hand(_spell), do: :mainhand

  defp ranged_crit_chance(%Character{} = caster, %Spell{} = spell) do
    Modifiers.value(caster, spell, :critical_chance, CombatRatings.crit_chance(caster, :ranged))
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

    Map.new(@schools, fn school ->
      {school,
       Map.get(bonuses, :"spell_#{school}", 0) + temporary_spell_damage(caster, school) +
         stat_scaled_spell_damage(caster, school)}
    end)
  end

  defp temporary_spell_damage(%{unit: %Unit{auras: holders}} = caster, school) when is_list(holders) do
    unrestricted =
      Enum.filter(holders, fn %Holder{spell: %Spell{} = spell} ->
        spell.equipped_item_class in [nil, -1] and spell.equipped_item_inventory_type_mask in [nil, 0]
      end)

    Aura.flat_modifier(
      %{caster | unit: %{caster.unit | auras: unrestricted}},
      :mod_damage_done,
      Spell.school_mask(school)
    )
  end

  defp temporary_spell_damage(_caster, _school), do: 0

  defp healing_bonus(caster, spell) do
    equipment = caster |> equipment_bonuses() |> Map.get(:healing, 0)

    equipment + Aura.flat_modifier(caster, :mod_healing_done, Spell.school_mask(spell)) +
      stat_scaled_amount(caster, :mod_spell_healing_of_stat_percent, 1)
  end

  defp stat_scaled_spell_damage(caster, school) do
    stat_scaled_amount(caster, :mod_spell_damage_of_stat_percent, Spell.school_mask(school))
  end

  defp stat_scaled_amount(%{unit: unit} = caster, aura_type, school_mask) do
    percent = Aura.flat_modifier(caster, aura_type, school_mask)
    spirit = unit.spirit || 0

    if percent > 0, do: trunc(spirit * percent / 100), else: 0
  end

  defp healing_done_multiplier(caster, %Spell{} = spell) do
    effect_multiplier(caster, spell, [:all_effects]) *
      Aura.percent_multiplier(caster, :mod_healing_done_percent, Spell.school_mask(spell))
  end

  defp equipment_bonuses(%{unit: %{equipment_bonuses: %{} = bonuses}}), do: bonuses
  defp equipment_bonuses(_caster), do: %{}
end
