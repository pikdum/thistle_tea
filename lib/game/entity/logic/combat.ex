defmodule ThistleTea.Game.Entity.Logic.Combat do
  @moduledoc """
  Melee auto-attack logic shared by players and mobs: attack timing, damage
  rolls from unit damage ranges, and applying an incoming attack to an entity
  along with the events it produces.
  """
  import Bitwise, only: [band: 2, bnot: 1, bor: 2, &&&: 2, >>>: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math

  @default_attack_speed_ms 2000
  @default_damage 2
  @unit_flag_in_combat 0x00080000
  @hitinfo_absorb 0x20
  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @base_melee_range_offset 1.333
  @attack_distance 5.0
  @chase_distance_inset 0.5
  @chase_rechase_range_factor 0.75

  def attack_speed_ms(%{unit: %Unit{base_attack_time: attack_time}} = entity)
      when is_integer(attack_time) and attack_time > 0 do
    haste = Aura.flat_amount(entity, :mod_melee_haste)

    if haste == 0 do
      attack_time
    else
      trunc(attack_time * 100 / max(100 + haste, 1))
    end
  end

  def attack_speed_ms(_entity), do: @default_attack_speed_ms

  def offhand_attack_speed_ms(%{unit: %Unit{offhand_attack_time: attack_time}} = entity)
      when is_integer(attack_time) and attack_time > 0 do
    haste = Aura.flat_amount(entity, :mod_melee_haste)
    trunc(attack_time * 100 / max(100 + haste, 1))
  end

  def offhand_attack_speed_ms(_entity), do: nil

  def offhand_damage_range(%{unit: %Unit{min_offhand_damage: min, max_offhand_damage: max}} = entity)
      when is_number(min) and is_number(max) and max > 0 do
    outgoing_damage_range(entity, {min * 0.5, max * 0.5})
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

  def damage_range(
        %{
          unit: %Unit{min_damage: min_damage, max_damage: max_damage},
          internal: %Internal{creature: %Creature{damage_multiplier: damage_multiplier}}
        } = entity
      )
      when is_number(min_damage) and is_number(max_damage) do
    multiplier = damage_multiplier(damage_multiplier)

    outgoing_damage_range(entity, {min_damage * multiplier, max_damage * multiplier})
  end

  def damage_range(%{unit: %Unit{min_damage: min_damage, max_damage: max_damage}} = entity)
      when is_number(min_damage) and is_number(max_damage) do
    outgoing_damage_range(entity, {min_damage, max_damage})
  end

  def damage_range(_entity), do: {@default_damage, @default_damage}

  @physical_school_mask 0x1
  @disarmed_damage_factor 0.5

  defp scale_damage_range(range, 1.0), do: range
  defp scale_damage_range({min_damage, max_damage}, multiplier), do: {min_damage * multiplier, max_damage * multiplier}

  defp outgoing_damage_range(entity, {min_damage, max_damage}) do
    flat = Aura.flat_modifier(entity, :mod_damage_done, @physical_school_mask)

    {max(min_damage + flat, 0), max(max_damage + flat, 0)}
    |> scale_damage_range(outgoing_damage_multiplier(entity))
  end

  defp outgoing_damage_multiplier(entity) do
    base = Aura.percent_multiplier(entity, :mod_damage_percent_done, @physical_school_mask)

    if Aura.has_aura?(entity, :mod_disarm) do
      base * @disarmed_damage_factor
    else
      base
    end
  end

  def attack_damage(%{damage: damage}) when is_number(damage), do: trunc(damage)

  def attack_damage(%{min_damage: min_damage, max_damage: max_damage})
      when is_number(min_damage) and is_number(max_damage) do
    min_value = min(min_damage, max_damage)
    max_value = max(min_damage, max_damage)
    Math.random_int(min_value, max_value)
  end

  def attack_damage(_attack), do: @default_damage

  defp damage_multiplier(multiplier) when is_number(multiplier) and multiplier > 0, do: multiplier
  defp damage_multiplier(_multiplier), do: 1.0

  def finalize_attack(attack) when is_map(attack) do
    Map.put_new(attack, :damage, attack_damage(attack))
  end

  def finalize_attack(attack), do: attack

  def attack_start(attacker, target) when is_integer(attacker) and is_integer(target) do
    Event.attack_start(attacker, target)
  end

  def attacker_state_update(attacker, target, damage, attack \\ %{}) when is_integer(attacker) and is_integer(target) do
    Event.attacker_state_update(attacker, target, damage, attack)
  end

  def receive_attack(entity, attack, now, opts \\ [])

  def receive_attack(%{object: %{guid: target_guid}} = entity, attack, now, opts)
      when is_map(attack) and is_integer(target_guid) and is_integer(now) do
    result = AttackTable.resolve(entity, attack, attack_damage(attack), opts)

    {entity, absorbed} =
      if result.damage > 0 do
        Core.take_damage_with_absorb(entity, result.damage, now,
          school: attack_school(attack),
          source: Map.get(attack, :caster, 0),
          threat_multiplier: Map.get(attack, :threat_multiplier, 1.0)
        )
      else
        {entity, 0}
      end

    attack =
      attack
      |> Map.put(:hit_info, with_absorb_flag(result.hit_info, absorbed))
      |> Map.put(:damage_state, result.victim_state)
      |> Map.put(:blocked_amount, result.blocked_amount)
      |> Map.put(:absorb, absorbed)

    entity = maybe_mark_defense(entity, Map.get(attack, :caster), result.outcome, now)
    event = attacker_state_update(Map.get(attack, :caster, 0), target_guid, result.damage, attack)
    feedback_events = attack_outcome_events(entity, attack, result, absorbed)

    {entity, reaction_events} =
      if result.damage > 0 do
        attack_reactions(entity, attack)
      else
        {entity, []}
      end

    entity = maybe_defense_skill_up(entity, attack, opts)

    {entity, [event | reaction_events] ++ feedback_events}
  end

  def receive_attack(entity, _attack, _now, _opts), do: {entity, []}

  defp maybe_defense_skill_up(%Character{unit: unit, player: player} = entity, attack, opts) do
    skill_up_opts = [
      player_level: unit.level || 1,
      mob_level: Map.get(attack, :caster_level) || unit.level || 1,
      defense?: true,
      roll: Keyword.get(opts, :skill_roll, fn chance -> :rand.uniform() * 100.0 < chance end)
    ]

    with false <- Map.get(attack, :caster_player?, false),
         {:gained, skills} <- Skills.combat_skill_up(player.skills, Skills.defense_skill(), skill_up_opts) do
      Core.mark_broadcast_update(%{entity | player: %{player | skills: skills}})
    else
      _no_gain -> entity
    end
  end

  defp maybe_defense_skill_up(entity, _attack, _opts), do: entity

  defp maybe_mark_defense(entity, attacker_guid, outcome, now) when outcome in [:dodge, :parry, :block] do
    Reactive.mark_defense(entity, attacker_guid, outcome, now)
  end

  defp maybe_mark_defense(entity, _attacker_guid, _outcome, _now), do: entity

  defp attack_outcome_events(%{object: %{guid: victim_guid}}, %{caster: caster} = attack, result, absorbed)
       when is_integer(caster) do
    if Guid.entity_type(caster) == :player do
      damage = outcome_damage_basis(attack, result, absorbed)

      [
        Event.attack_outcome(
          caster,
          victim_guid,
          result.outcome,
          damage,
          Map.get(attack, :queued_spell_id),
          outcome_proc_damage(result, absorbed)
        )
      ]
    else
      []
    end
  end

  defp attack_outcome_events(_entity, _attack, _result, _absorbed), do: []

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

  defp attack_school(%{spell_school_mask: mask}) when is_integer(mask) and mask > 1 do
    index = Enum.find(1..6, 0, fn i -> (mask >>> i &&& 1) == 1 end)
    Enum.at(@schools, index, :physical)
  end

  defp attack_school(_attack), do: :physical

  defp with_absorb_flag(hit_info, absorbed) when is_integer(absorbed) and absorbed > 0 do
    bor(hit_info, @hitinfo_absorb)
  end

  defp with_absorb_flag(hit_info, _absorbed), do: hit_info

  defp attack_reactions(entity, %{caster: attacker_guid}) when is_integer(attacker_guid) do
    if Core.dead?(entity) do
      {entity, []}
    else
      Aura.reactions(entity, :hit_taken, %{attacker_guid: attacker_guid})
    end
  end

  defp attack_reactions(entity, _attack), do: {entity, []}
end
