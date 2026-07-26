defmodule ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal do
  @moduledoc false
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Druid
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.Rogue
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Critical
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Semantics

  @creature_type_humanoid 7
  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]
  @weapon_effect_types [:weapon_damage, :weapon_damage_noschool, :normalized_weapon_damage, :weapon_percent_damage]

  def apply(state, %CastContext{} = context, spell, %Effect{type: :school_damage} = effect, now) do
    result =
      cond do
        Warlock.conflagrate?(spell) and not Warlock.has_immolate_from?(state, context.caster_guid) ->
          {state, []}

        Spell.melee_ability?(spell) ->
          melee_ability_damage(state, context, spell, school_damage_roll(context, spell, effect), now)

        true ->
          apply_damage_effect(state, context, spell, effect, now)
      end

    result
    |> consume_conflagrate_immolate(context, spell, now)
    |> consume_ferocious_bite_energy(context, spell)
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :health_leech} = effect, now) do
    health_before = max(state.unit.health || 0, 0)
    {state, events} = apply_damage_effect(state, context, spell, effect, now)
    damage = min(dealt_damage(events), health_before)
    healed = trunc(damage * leech_multiplier(effect))
    {state, events ++ if(healed > 0, do: [Effects.heal_entity(context.caster_guid, healed)], else: [])}
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :instakill}, now) do
    events =
      if Warlock.demonic_sacrifice?(spell) do
        case Warlock.sacrifice_event(state, context) do
          nil -> []
          event -> [event]
        end
      else
        []
      end

    {Core.take_damage(
       state,
       state.unit.health || 0,
       now,
       damage_source_opts(context) ++ [spell_id: spell.id]
     ), events}
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :heal} = effect, now) do
    {state, swiftmend_healing, swiftmend_events} = Druid.consume_swiftmend_hot(state, spell, now)

    base_healing =
      trunc((rolled_amount(spell, effect, context) + swiftmend_healing) * (context.effect_healing_multiplier || 1.0))

    healing =
      base_healing + Coefficient.bonus(context.healing_bonus || 0, spell, effect, :direct) +
        Aura.flat_modifier(state, :mod_healing, Spell.school_mask(spell)) +
        Paladin.blessing_of_light_bonus(state, spell)

    healing = max(trunc(healing * healing_taken_multiplier(state, spell)), 0)
    crit? = heal_crit?(context, spell)
    healing = if crit?, do: healing + div(healing, 2), else: healing
    events = Threat.heal_threat_events(state, context.caster_guid, healing)
    heal_event = Effects.spell_heal(context.caster_guid, state.object.guid, spell, healing, crit?)

    {Core.heal(state, healing), swiftmend_events ++ events ++ [heal_event]}
  end

  def apply(state, %CastContext{} = context, _spell, %Effect{type: :heal_max_health}, _now) do
    healing = max(context.caster_max_health || state.unit.max_health || 0, 0)
    events = Threat.heal_threat_events(state, context.caster_guid, healing)
    {Core.heal(state, healing), events}
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  def apply_weapon_group(state, %CastContext{} = context, spell, now) do
    effects = Enum.filter(context.spell.effects, &weapon_effect?/1)
    context = apply_target_attack_power_bonus(state, context, spell)

    base =
      if Enum.any?(effects, &(&1.type == :normalized_weapon_damage)),
        do: normalized_weapon_roll(context),
        else: weapon_roll(context)

    flat =
      effects
      |> Enum.reject(&(&1.type == :weapon_percent_damage))
      |> Enum.map(&rolled_amount(spell, &1, context))
      |> Enum.sum()

    percent =
      effects
      |> Enum.filter(&(&1.type == :weapon_percent_damage))
      |> Enum.reduce(1.0, fn effect, acc -> acc * rolled_amount(spell, effect, context) / 100 end)

    melee_ability_damage(state, context, spell, trunc((base + flat) * percent), now)
  end

  def execute(state, %CastContext{} = context, spell, %Effect{} = effect, now) do
    rage = context.caster_power || 0
    damage = rolled_amount(spell, effect, context) + trunc(rage * effect.damage_multiplier)
    damage_spell = %{spell | id: Scripts.execute_damage_spell_id()}

    {state, events} = melee_ability_damage(state, context, damage_spell, damage, now)
    {state, events ++ [Effects.drain_power(context.caster_guid, 1)]}
  end

  def avoided_melee_ability_reactions(state, context, spell, outcome, now) do
    incoming_melee_ability_reactions(state, context, spell, outcome, now)
  end

  defp weapon_effect?(%Effect{type: type}), do: type in @weapon_effect_types

  defp apply_target_attack_power_bonus(state, %CastContext{} = context, %Spell{} = spell) do
    if Spell.ranged_ability?(spell) do
      bonus = Aura.flat_amount(state, :ranged_attack_power_attacker_bonus)
      %{context | attack_power: (context.attack_power || 0) + bonus}
    else
      context
    end
  end

  defp leech_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp leech_multiplier(_effect), do: 1.0

  defp heal_crit?(%CastContext{spell_crit_chance: chance}, %Spell{} = spell) when is_number(chance) and chance > 0 do
    not Spell.attribute?(spell, :cant_crit) and (chance >= 100 or :rand.uniform() * 100 <= chance)
  end

  defp heal_crit?(_context, _spell), do: false

  defp healing_taken_multiplier(state, spell) do
    percent = Aura.flat_modifier(state, :mod_healing_pct, Spell.school_mask(spell))
    max(100 + percent, 0) / 100
  end

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, now, opts \\ [])
       when is_integer(now) do
    base = effect_amount(spell, effect, context)
    rolled = base + damage_bonus(context, spell, effect, opts)

    rolled =
      trunc(
        rolled * (context.effect_damage_multiplier || 1.0) * (context.damage_done_multiplier || 1.0) *
          versus_damage_multiplier(state, context) * scripted_damage_multiplier(state, spell)
      )

    crit? = direct_spell_crit?(state, context, spell, opts)
    rolled = if crit?, do: rolled + versus_crit_bonus(state, context, crit_bonus(context, spell, rolled)), else: rolled

    damage = max(rolled + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    school = school_atom(spell)
    resisted = school_resisted_amount(state, damage, school, context, opts)
    damage = damage - resisted

    {state, absorbed} =
      Core.take_damage_with_absorb(state, damage, now,
        school: school,
        source: context.caster_guid,
        source_owner: context.caster_owner_guid,
        reflected_by: context.reflected_by_guid,
        threat_multiplier: damage_threat_multiplier(context)
      )

    event =
      Effects.spell_damage(
        context.caster_guid,
        state.object.guid,
        spell,
        damage,
        Keyword.put_new(opts, :proc_type, dealt_spell_proc_type(spell, opts)) ++
          [resisted: resisted, absorbed: absorbed, crit?: crit?]
      )

    {state, reaction_events} = spell_taken_reactions(state, context, spell, damage, crit?, opts, now)
    {state, [event | reaction_events]}
  end

  defp spell_taken_reactions(state, %CastContext{caster_guid: caster_guid}, spell, damage, crit?, opts, now)
       when is_integer(caster_guid) and is_integer(damage) and damage > 0 do
    proc_type = taken_spell_proc_type(spell, opts)
    reaction = if proc_type == :take_ranged_ability, do: :hit_taken, else: :spell_hit_taken

    Aura.reactions(state, reaction, %{
      attacker_guid: caster_guid,
      spell: spell,
      proc_type: proc_type,
      outcome: if(crit?, do: :crit, else: :normal),
      damage: damage,
      now: now
    })
  end

  defp spell_taken_reactions(state, _context, _spell, _damage, _crit?, _opts, _now), do: {state, []}

  defp versus_damage_multiplier(state, %CastContext{damage_done_versus: pairs}) do
    max(100 + Aura.versus_amount(pairs, creature_type_mask(state)), 0) / 100
  end

  defp versus_crit_bonus(state, %CastContext{crit_damage_versus: pairs}, bonus) do
    trunc(bonus * max(100 + Aura.versus_amount(pairs, creature_type_mask(state)), 0) / 100)
  end

  defp creature_type_mask(%{creature_type: creature_type}) when is_integer(creature_type) and creature_type > 0 do
    1 <<< (creature_type - 1)
  end

  defp creature_type_mask(_state), do: 1 <<< (@creature_type_humanoid - 1)

  defp scripted_damage_multiplier(state, %Spell{} = spell) do
    if Semantics.rules(spell).judgement_damage? do
      if Aura.has_aura?(state, :mod_stun), do: 1.0, else: 0.5
    else
      1.0
    end
  end

  defp direct_spell_crit?(state, %CastContext{spell_crit_chance: chance} = context, %Spell{} = spell, opts)
       when is_number(chance) do
    chance =
      chance +
        Aura.flat_amount(state, :mod_attacker_spell_crit_chance) +
        Critical.target_bonus(context.conditional_crit_modifiers, state)

    chance > 0 and not Keyword.get(opts, :periodic?, false) and not Spell.attribute?(spell, :cant_crit) and
      spell.dmg_class in [1, 3] and (chance >= 100 or :rand.uniform() * 100 <= chance)
  end

  defp direct_spell_crit?(_state, _context, _spell, _opts), do: false

  defp crit_bonus(%CastContext{} = context, %Spell{} = spell, damage) do
    base_bonus = damage * (spell_crit_multiplier(spell) - 1.0)
    trunc(Modifiers.value(context.spell_modifiers, :crit_damage_bonus, base_bonus))
  end

  defp spell_crit_multiplier(%Spell{dmg_class: 3}), do: 2.0
  defp spell_crit_multiplier(%Spell{}), do: 1.5

  defp school_resisted_amount(_state, damage, _school, _context, _opts) when damage <= 0, do: 0
  defp school_resisted_amount(_state, _damage, :physical, _context, _opts), do: 0

  defp school_resisted_amount(%{unit: unit} = state, damage, school, %CastContext{} = context, opts) do
    caster_level =
      if is_integer(context.caster_level) and context.caster_level > 0, do: context.caster_level, else: 1

    resistance = max((Map.get(unit, :"#{school}_resistance") || 0) + (context.spell_penetration || 0), 0)
    target_creature? = not is_map(Map.get(state, :player))
    level_diff = (unit.level || 1) - caster_level

    SpellResist.resisted_amount(damage, resistance, caster_level,
      target_creature?: target_creature?,
      level_diff: level_diff,
      dot?: Keyword.get(opts, :periodic?, false)
    )
  end

  defp damage_bonus(%CastContext{} = context, %Spell{} = spell, %Effect{} = effect, opts) do
    if Keyword.get(opts, :periodic?, false) do
      0
    else
      school_bonus = Map.get(context.spell_damage_bonus, school_atom(spell), 0)
      Coefficient.bonus(school_bonus, spell, effect, :direct)
    end
  end

  defp school_atom(%Spell{school: school}) when is_atom(school), do: school
  defp school_atom(%Spell{} = spell), do: Enum.at(@schools, Spell.school_index(spell), :physical)

  defp school_damage_roll(%CastContext{} = context, spell, %Effect{} = effect) do
    roll =
      effect_amount(spell, effect, context) +
        eviscerate_attack_power(spell, context) +
        Druid.ferocious_bite_bonus(
          spell,
          context.attack_power,
          context.combo_points,
          context.caster_power,
          effect.damage_multiplier
        ) +
        Warrior.shield_slam_bonus(spell, effect, context.shield_block_value)

    if Semantics.rules(spell).attack_power_damage? do
      trunc(roll * (context.attack_power || 0) / 100)
    else
      roll
    end
  end

  defp effect_amount(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    level_units = Spell.level_units(spell, context.caster_level)

    if Scripts.finisher?(spell) do
      Effect.amount(effect, level_units, context.combo_points || 0)
    else
      Effect.roll(effect, level_units)
    end
  end

  defp rolled_amount(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    Effect.roll(effect, Spell.level_units(spell, context.caster_level))
  end

  defp eviscerate_attack_power(%Spell{} = spell, %CastContext{} = context) do
    if Rogue.eviscerate?(spell) do
      trunc((context.attack_power || 0) * (context.combo_points || 0) * 0.03)
    else
      0
    end
  end

  defp weapon_roll(%CastContext{attack_time_ms: attack_time_ms} = context)
       when is_number(attack_time_ms) and attack_time_ms > 0 do
    weapon_base_roll(context) + attack_power_bonus_ms(context, attack_time_ms)
  end

  defp weapon_roll(%CastContext{} = context), do: weapon_base_roll(context)

  defp normalized_weapon_roll(%CastContext{normalized_speed: speed} = context) when is_number(speed) and speed > 0 do
    weapon_base_roll(context) + attack_power_bonus(context, speed)
  end

  defp normalized_weapon_roll(%CastContext{} = context), do: weapon_roll(context)

  defp weapon_base_roll(%CastContext{weapon_base_min: min, weapon_base_max: max})
       when is_number(min) and is_number(max) do
    Math.random_int(trunc(min), max(trunc(max), trunc(min)))
  end

  defp weapon_base_roll(_context), do: 0

  defp attack_power_bonus(%CastContext{attack_power: attack_power}, speed_seconds)
       when is_integer(attack_power) and attack_power > 0 do
    trunc(attack_power / 14 * speed_seconds)
  end

  defp attack_power_bonus(_context, _speed_seconds), do: 0

  defp attack_power_bonus_ms(%CastContext{attack_power: attack_power}, attack_time_ms)
       when is_integer(attack_power) and attack_power > 0 and is_integer(attack_time_ms) do
    div(attack_power * attack_time_ms, 14_000)
  end

  defp attack_power_bonus_ms(context, attack_time_ms), do: attack_power_bonus(context, attack_time_ms / 1_000)

  defp melee_ability_damage(state, %CastContext{} = context, spell, damage, now) do
    school = school_atom(spell)

    damage =
      trunc(damage * (context.effect_damage_multiplier || 1.0) * (context.damage_done_multiplier || 1.0))

    unmitigated_damage =
      max(damage + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    damage = mitigate_physical(state, context, school, unmitigated_damage)

    damage =
      if context.melee_crit? do
        damage + trunc(Modifiers.value(context.spell_modifiers, :crit_damage_bonus, damage * 1.0))
      else
        damage
      end

    proc_damage = if context.melee_crit?, do: unmitigated_damage * 2, else: unmitigated_damage

    {state, absorbed} =
      Core.take_damage_with_absorb(state, damage, now,
        school: school,
        source: context.caster_guid,
        source_owner: context.caster_owner_guid,
        reflected_by: context.reflected_by_guid,
        threat_multiplier: damage_threat_multiplier(context)
      )

    event =
      Effects.spell_damage(context.caster_guid, state.object.guid, spell, damage,
        absorbed: absorbed,
        crit?: context.melee_crit? || false,
        proc_damage: proc_damage,
        proc_type: dealt_attack_proc_type(spell)
      )

    {state, reaction_events} = melee_ability_reactions(state, context, spell, damage - absorbed, now)
    {state, [event | reaction_events]}
  end

  defp melee_ability_reactions(state, %CastContext{} = context, %Spell{} = spell, damage, now) when damage > 0 do
    outcome = if context.melee_crit?, do: :crit, else: :normal
    incoming_melee_ability_reactions(state, context, spell, outcome, now)
  end

  defp melee_ability_reactions(state, _context, _spell, _damage, _now), do: {state, []}

  defp incoming_melee_ability_reactions(state, %CastContext{} = context, %Spell{} = spell, outcome, now) do
    if Core.dead?(state) do
      {state, []}
    else
      Aura.reactions(state, :hit_taken, %{
        attacker_guid: context.caster_guid,
        attacker_position: attack_position(context.caster_position),
        proc_type: taken_attack_proc_type(spell),
        outcome: outcome,
        spell: spell,
        now: now
      })
    end
  end

  defp dealt_spell_proc_type(%Spell{} = spell, opts) when is_list(opts) do
    cond do
      Keyword.get(opts, :periodic?, false) -> :deal_harmful_periodic
      Spell.ranged_ability?(spell) -> :deal_ranged_ability
      true -> :deal_harmful_spell
    end
  end

  defp taken_spell_proc_type(%Spell{} = spell, opts) when is_list(opts) do
    cond do
      Keyword.get(opts, :periodic?, false) -> :take_harmful_periodic
      Spell.ranged_ability?(spell) -> :take_ranged_ability
      true -> :take_harmful_spell
    end
  end

  defp dealt_attack_proc_type(%Spell{} = spell) do
    cond do
      Hunter.auto_shot?(spell) -> :deal_ranged_attack
      Spell.ranged_ability?(spell) -> :deal_ranged_ability
      true -> :deal_melee_ability
    end
  end

  defp taken_attack_proc_type(%Spell{} = spell) do
    cond do
      Hunter.auto_shot?(spell) -> :take_ranged_attack
      Spell.ranged_ability?(spell) -> :take_ranged_ability
      true -> :take_melee_ability
    end
  end

  defp mitigate_physical(%{unit: %{normal_resistance: armor}}, %CastContext{} = context, :physical, damage)
       when damage > 0 do
    AttackTable.armor_reduced_damage(damage, armor || 0, context.caster_level)
  end

  defp mitigate_physical(_state, _context, _school, damage), do: damage

  defp damage_threat_multiplier(%CastContext{} = context) do
    base = context.threat_multiplier || 1.0

    case context.spell_threat do
      %{multiplier: multiplier} when is_number(multiplier) -> base * multiplier
      _no_entry -> base
    end
  end

  defp attack_position({_map, x, y, z}), do: {x, y, z}
  defp attack_position(_position), do: nil

  defp consume_conflagrate_immolate({state, events}, %CastContext{caster_guid: caster_guid}, spell, now) do
    if Warlock.conflagrate?(spell) do
      {state, aura_events} = Warlock.consume_immolate(state, caster_guid, now)
      {state, events ++ aura_events}
    else
      {state, events}
    end
  end

  defp damage_source_opts(%CastContext{} = context) do
    [
      source: context.caster_guid,
      source_owner: context.caster_owner_guid,
      reflected_by: context.reflected_by_guid
    ]
  end

  defp consume_ferocious_bite_energy({state, events}, %CastContext{} = context, %Spell{} = spell) do
    if Druid.ferocious_bite?(spell) do
      {state, events ++ [Effects.drain_power(context.caster_guid, 3)]}
    else
      {state, events}
    end
  end

  defp dealt_damage(events) do
    Enum.reduce(events, 0, fn
      %Effects.SpellDamage{damage: damage, absorbed: absorbed}, acc when is_integer(damage) ->
        acc + max(damage - (absorbed || 0), 0)

      _event, acc ->
        acc
    end)
  end
end
