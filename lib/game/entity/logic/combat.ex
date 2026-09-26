defmodule ThistleTea.Game.Entity.Logic.Combat do
  @moduledoc """
  Melee auto-attack logic shared by players and mobs: attack timing, damage
  rolls from unit damage ranges, and applying an incoming attack to an entity
  along with the events it produces.
  """
  import Bitwise, only: [band: 2, bnot: 1, bor: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackSchool
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Daze
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ParryHaste
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Entity.Logic.WeaponProcs
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Proc

  @default_attack_speed_ms 2000
  @default_damage 2
  @unit_flag_in_combat 0x00080000
  @hitinfo_absorb 0x20
  @hitinfo_resist 0x40

  @base_melee_range_offset 1.333
  @attack_distance 5.0
  @chase_distance_inset 0.5
  @chase_rechase_range_factor 0.75

  def attack_speed_ms(%{unit: %Unit{base_attack_time: attack_time}}) when is_integer(attack_time) and attack_time > 0 do
    attack_time
  end

  def attack_speed_ms(_entity), do: @default_attack_speed_ms

  def offhand_attack_speed_ms(%{unit: %Unit{offhand_attack_time: attack_time}})
      when is_integer(attack_time) and attack_time > 0 do
    attack_time
  end

  def offhand_attack_speed_ms(_entity), do: nil

  def offhand_damage_range(%{unit: %Unit{min_offhand_damage: min, max_offhand_damage: max}} = entity)
      when is_number(min) and is_number(max) and max > 0 do
    factor = 0.5 * max(100 + Aura.flat_amount(entity, :mod_offhand_damage_pct), 0) / 100

    entity
    |> outgoing_damage_range({min, max}, :offhand)
    |> scale_damage_range(factor)
  end

  def offhand_damage_range(_entity), do: nil

  def sync_combat_flag(%{unit: %Unit{} = unit, internal: %Internal{in_combat: in_combat}} = entity) do
    updated = combat_flags(unit.flags || 0, in_combat)

    if updated == unit.flags do
      entity
    else
      %{entity | unit: %{unit | flags: updated}}
      |> Core.mark_broadcast_update()
    end
  end

  def sync_combat_flag(entity), do: entity

  defp combat_flags(flags, true), do: bor(flags, @unit_flag_in_combat)
  defp combat_flags(flags, in_combat) when in_combat in [false, nil], do: band(flags, bnot(@unit_flag_in_combat))

  def melee_reach(attacker_reach, target_reach) when is_number(attacker_reach) and is_number(target_reach) do
    max(attacker_reach + target_reach + @base_melee_range_offset, @attack_distance)
  end

  def chase_target_distance(melee_reach) when is_number(melee_reach) do
    max(melee_reach - @chase_distance_inset, 0.0)
  end

  def chase_rechase_distance(melee_reach, target_bounding_radius)
      when is_number(melee_reach) and is_number(target_bounding_radius) do
    max(melee_reach * @chase_rechase_range_factor - target_bounding_radius, 0.0)
  end

  def damage_range(%{unit: %Unit{min_damage: min_damage, max_damage: max_damage}} = entity)
      when is_number(min_damage) and is_number(max_damage) do
    mainhand_damage_range(entity, {min_damage, max_damage})
  end

  def damage_range(_entity), do: {@default_damage, @default_damage}

  defp scale_damage_range(range, 1.0), do: range
  defp scale_damage_range({min_damage, max_damage}, multiplier), do: {min_damage * multiplier, max_damage * multiplier}

  defp mainhand_damage_range(entity, range) do
    entity
    |> outgoing_damage_range(range, :mainhand)
    |> scale_damage_range(Disarm.damage_multiplier(entity))
  end

  defp outgoing_damage_range(entity, {min_damage, max_damage}, hand) do
    weapon = CombatWeapon.usable(entity, hand)
    school = AttackSchool.melee(entity)
    flat = WeaponDamage.flat_bonus(entity, school, weapon) - WeaponDamage.projected_flat_bonus(entity.unit, hand)
    happiness = PetHappiness.damage_multiplier(entity)
    flat = if happiness == 1.0, do: flat, else: flat * happiness

    {max(min_damage + flat, 0), max(max_damage + flat, 0)}
    |> scale_damage_range(WeaponDamage.multiplier(entity, school, weapon))
  end

  def attack_damage(%{damage: damage}) when is_number(damage), do: trunc(damage)

  def attack_damage(%{min_damage: min_damage, max_damage: max_damage})
      when is_number(min_damage) and is_number(max_damage) do
    min_value = min(min_damage, max_damage)
    max_value = max(min_damage, max_damage)
    Math.random_int(min_value, max_value)
  end

  def attack_damage(_attack), do: @default_damage

  def finalize_attack(attack) when is_map(attack) do
    Map.put_new(attack, :damage, attack_damage(attack))
  end

  def finalize_attack(attack), do: attack

  def attack_start(attacker, target) when is_integer(attacker) and is_integer(target) do
    Effects.attack_start(attacker, target)
  end

  def attacker_state_update(attacker, target, damage, attack \\ %{}) when is_integer(attacker) and is_integer(target) do
    Effects.attacker_state_update(attacker, target, damage, attack)
  end

  def receive_attack(entity, attack, now, opts \\ [])

  def receive_attack(%{unit: %Unit{health: health}} = entity, _attack, _now, _opts)
      when is_integer(health) and health <= 0, do: {entity, []}

  def receive_attack(%{object: %{guid: target_guid}} = entity, attack, now, opts)
      when is_map(attack) and is_integer(target_guid) and is_integer(now) do
    result = resolve_attack(entity, attack, opts)
    resisted = resisted_damage(entity, attack, result.damage, opts)
    result = %{result | damage: result.damage - resisted}
    skill_opts = Keyword.take(opts, [:skill_roll]) |> Keyword.new(fn {:skill_roll, roll} -> {:roll, roll} end)
    {entity, skill_events} = CombatSkills.resolve(entity, attack, result.outcome, skill_opts)
    entity = ParryHaste.apply(entity, result.outcome, now)

    {entity, damage, absorbed} =
      if result.damage > 0 do
        Core.take_damage_with_mitigation(entity, result.damage, now,
          school: attack_school(attack),
          source: Map.get(attack, :caster, 0),
          source_level: Map.get(attack, :caster_level, 1),
          resistance_penetration: Map.get(attack, :resistance_penetration, []),
          source_owner: Map.get(attack, :caster_owner_guid),
          damage_sharing_targets: Keyword.get(opts, :damage_sharing_targets, MapSet.new()),
          threat_multiplier: Map.get(attack, :threat_multiplier, 1.0)
        )
      else
        {entity, 0, 0}
      end

    result =
      result
      |> Map.put(:proc_ex, Proc.hit_mask(result.outcome, result.damage, absorbed))
      |> Map.put(:damage, damage)

    attack =
      attack
      |> Map.put(:hit_info, with_damage_flags(result.hit_info, absorbed, resisted))
      |> Map.put(:damage_state, result.victim_state)
      |> Map.put(:blocked_amount, result.blocked_amount)
      |> Map.put(:absorb, absorbed)
      |> Map.put(:resist, resisted)

    entity = maybe_mark_defense(entity, Map.get(attack, :caster), result.outcome, now)
    event = attacker_state_update(Map.get(attack, :caster, 0), target_guid, max(result.damage - absorbed, 0), attack)
    feedback_events = attack_outcome_events(entity, attack, result, absorbed)

    {entity, reaction_events} = attack_reactions(entity, attack, result, now)

    daze_roll = Keyword.get(opts, :daze_roll, fn -> :rand.uniform() * 100 end)
    daze_events = Daze.events(entity, attack, result.damage - absorbed, daze_roll)

    weapon_procs = WeaponProcs.swing_events(entity, attack, result, absorbed)
    {entity, daze_events ++ [event | reaction_events] ++ feedback_events ++ skill_events ++ weapon_procs}
  end

  def receive_attack(entity, _attack, _now, _opts), do: {entity, []}

  defp resolve_attack(entity, attack, opts) do
    if DamageImmunity.immune?(entity, attack_school(attack)) do
      %{outcome: :immune, damage: 0, pre_armor_damage: 0, hit_info: 0x2, victim_state: 7, blocked_amount: 0}
    else
      AttackTable.resolve(entity, attack, attack_damage(attack), opts)
    end
  end

  defp resisted_damage(_entity, _attack, damage, _opts) when damage <= 0, do: 0

  defp resisted_damage(%{unit: %Unit{} = unit} = entity, attack, damage, opts) do
    school = attack_school(attack)

    if school == :physical do
      0
    else
      resistance =
        entity
        |> SpellResist.school_resistances()
        |> Map.fetch!(Spell.school_index(school))
        |> ResistancePenetration.resistance(Map.get(attack, :resistance_penetration, []), school)

      caster_level = Map.get(attack, :caster_level) || unit.level || 1

      SpellResist.resisted_amount(damage, resistance, caster_level,
        target_creature?: not is_struct(entity, Character),
        level_diff: (unit.level || 1) - caster_level,
        roll: Keyword.get_lazy(opts, :resist_roll, fn -> Math.random_int(0, 99) end)
      )
    end
  end

  defp maybe_mark_defense(entity, attacker_guid, outcome, now) when outcome in [:dodge, :parry, :block] do
    Reactive.mark_defense(entity, attacker_guid, outcome, now)
  end

  defp maybe_mark_defense(entity, _attacker_guid, _outcome, _now), do: entity

  defp attack_outcome_events(%{object: %{guid: victim_guid}}, %{caster: caster} = attack, result, absorbed)
       when is_integer(caster) do
    if Guid.entity_type(caster) in [:player, :mob] do
      damage = outcome_damage_basis(attack, result, absorbed)

      [
        %{
          Effects.attack_outcome(
            caster,
            victim_guid,
            result.outcome,
            damage,
            Map.get(attack, :queued_spell_id),
            outcome_proc_damage(result, absorbed)
          )
          | hand: attack_hand(attack),
            proc_ex: result.proc_ex,
            extra_attack?: Map.get(attack, :extra_attack?, false)
        }
      ]
    else
      []
    end
  end

  defp attack_outcome_events(_entity, _attack, _result, _absorbed), do: []

  defp attack_hand(%{ranged?: true}), do: :ranged
  defp attack_hand(%{offhand?: true}), do: :offhand
  defp attack_hand(_attack), do: :mainhand

  defp outcome_damage_basis(attack, %{outcome: outcome}, _absorbed) when outcome in [:dodge, :parry] do
    attack_damage(attack)
  end

  defp outcome_damage_basis(_attack, %{outcome: :miss}, _absorbed), do: 0

  defp outcome_damage_basis(_attack, %{damage: damage}, absorbed) when is_integer(damage) do
    max(damage - (absorbed || 0), 0)
  end

  defp outcome_damage_basis(_attack, _result, _absorbed), do: 0

  defp outcome_proc_damage(%{damage: damage, pre_armor_damage: pre_armor_damage}, absorbed)
       when is_integer(damage) and damage > 0 and is_integer(pre_armor_damage) do
    round(pre_armor_damage * max(damage - (absorbed || 0), 0) / damage)
  end

  defp outcome_proc_damage(_result, _absorbed), do: 0

  defp attack_school(%{spell_school_mask: mask}), do: AttackSchool.from_mask(mask)
  defp attack_school(_attack), do: :physical

  defp with_damage_flags(hit_info, absorbed, resisted) do
    hit_info = if absorbed > 0, do: bor(hit_info, @hitinfo_absorb), else: hit_info
    if resisted > 0, do: bor(hit_info, @hitinfo_resist), else: hit_info
  end

  defp attack_reactions(entity, %{caster: attacker_guid} = attack, %{outcome: outcome} = result, now)
       when is_integer(attacker_guid) do
    if Core.dead?(entity) do
      {entity, []}
    else
      proc_type = if is_integer(Map.get(attack, :spell_id)), do: :take_melee_ability, else: :take_melee_swing

      Aura.reactions(entity, :hit_taken, %{
        attacker_guid: attacker_guid,
        attacker_position: Map.get(attack, :caster_position),
        proc_type: proc_type,
        outcome: outcome,
        proc_ex: result.proc_ex,
        damage: max(result.damage - Map.get(attack, :absorb, 0), 0),
        absorbed: Map.get(attack, :absorb, 0),
        spell: Map.get(attack, :spell),
        triggering_spell_id: Map.get(attack, :spell_id),
        now: now
      })
    end
  end

  defp attack_reactions(entity, _attack, _result, _now), do: {entity, []}
end
