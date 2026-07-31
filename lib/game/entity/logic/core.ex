defmodule ThistleTea.Game.Entity.Logic.Core do
  @moduledoc """
  Entity operations generic across all entity types: building update-object
  payloads, taking damage and dying, healing, mana restoration, and combat
  tether-range checks for mobs.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CastPushback
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.WorldRef

  @extra_flag_no_leash_evade 0x00000001
  @leash_timeout_ms 6_000
  @spirit_of_redemption_talent 20_711
  @spirit_of_redemption_form 27_827
  @spirit_of_redemption_auras [27_827, 27_792, 27_795]
  @spirit_of_redemption_suicide 27_965
  @spirit_of_redemption_duration_ms 15_000

  def update_object(entity, update_type \\ :create_object2)
  def update_object(%Mob{} = entity, update_type), do: update_object(entity, update_type, :unit)
  def update_object(%GameObject{} = entity, update_type), do: update_object(entity, update_type, :game_object)
  def update_object(%Corpse{} = entity, update_type), do: update_object(entity, update_type, :corpse)

  def update_object(%DataDynamicObject{} = entity, update_type), do: update_object(entity, update_type, :dynamic_object)
  def update_object(%Character{} = entity, update_type), do: update_object(entity, update_type, :player)

  def update_object(entity, update_type, object_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: object_type
    }
    |> struct(Map.from_struct(entity))
  end

  def take_damage(entity, damage, now, opts \\ []) do
    {entity, _absorbed} = take_damage_with_absorb(entity, damage, now, opts)
    entity
  end

  def take_damage_with_absorb(entity, damage, now, opts \\ [])

  def take_damage_with_absorb(%{internal: %Internal{godmode: true}} = entity, _damage, _now, _opts), do: {entity, 0}

  def take_damage_with_absorb(entity, damage, now, opts) when is_number(damage) and damage > 0 and is_integer(now) do
    if Aura.school_immune?(entity, Keyword.get(opts, :school, :physical)) do
      {entity, damage}
    else
      take_unblocked_damage(entity, damage, now, opts)
    end
  end

  def take_damage_with_absorb(entity, _damage, _now, _opts), do: {entity, 0}

  defp take_unblocked_damage(%{unit: %Unit{health: health}} = entity, damage, now, opts) do
    if spirit_damage_immune?(entity, opts) do
      {entity, damage}
    else
      school = Keyword.get(opts, :school, :physical)
      damage = scale_damage_taken(entity, damage, school)
      {damage, redirect} = Aura.damage_redirect(entity, damage, school)
      entity = enqueue_redirect(entity, redirect, Keyword.get(opts, :source), school)
      {entity, remaining} = Aura.absorb_damage(entity, damage, school, now)
      %{unit: unit} = entity
      duel_outcome = duel_lethal_outcome(entity, health, remaining, opts)
      remaining = duel_remaining_damage(health, remaining, duel_outcome)
      remaining = invincibility_remaining_damage(entity, health, remaining)
      absorbed = damage - remaining
      new_health = max(health - remaining, 0)

      entity = %{entity | unit: %{unit | health: new_health}}
      entity = enqueue_duel_outcome(entity, duel_outcome)
      entity = Aura.enqueue_death_item_rewards(entity, health, new_health)

      entity =
        if remaining > 0 do
          entity
          |> Aura.break_on_damage(now)
          |> CastPushback.on_damage(now, opts)
        else
          entity
        end

      entity =
        entity
        |> gain_taken_rage(remaining, Keyword.get(opts, :source))
        |> Reactive.sync_health()
        |> Threat.add_damage(Keyword.get(opts, :source), damage * Keyword.get(opts, :threat_multiplier, 1.0))
        |> maybe_enqueue_death_root(health, new_health)
        |> maybe_prepare_self_res(health, new_health)
        |> maybe_record_killer(health, new_health, Keyword.get(opts, :source))
        |> maybe_enter_spirit_of_redemption(health, new_health, now, opts)
        |> mark_broadcast_update()
        |> maybe_dead(now)

      {entity, absorbed}
    end
  end

  defp take_unblocked_damage(entity, _damage, _now, _opts), do: {entity, 0}

  defp duel_lethal_outcome(entity, health, damage, opts)
       when is_number(health) and health > 0 and is_number(damage) and damage >= health do
    cond do
      Dueling.lethal_source?(entity, opts) -> {:defeated, Dueling.opponent_guid(entity)}
      Dueling.active?(entity) -> :interrupted
      true -> nil
    end
  end

  defp duel_lethal_outcome(_entity, _health, _damage, _opts), do: nil

  defp duel_remaining_damage(health, damage, {:defeated, _winner_guid}), do: min(damage, max(health - 1, 0))
  defp duel_remaining_damage(_health, damage, _outcome), do: damage

  defp invincibility_remaining_damage(%{internal: %Internal{invincibility_health_threshold: threshold}}, health, damage)
       when is_integer(threshold) and threshold > 0 do
    min(damage, max(health - threshold, 0))
  end

  defp invincibility_remaining_damage(_entity, _health, damage), do: damage

  defp enqueue_duel_outcome(entity, {:defeated, winner_guid}) when is_integer(winner_guid) do
    Effects.enqueue(entity, Effects.duel_defeat(entity.object.guid, winner_guid))
  end

  defp enqueue_duel_outcome(entity, :interrupted) do
    Effects.enqueue(entity, Effects.duel_interrupted(entity.object.guid))
  end

  defp enqueue_duel_outcome(entity, _outcome), do: entity

  defp enqueue_redirect(entity, {target_guid, amount}, source_guid, school) when is_integer(amount) and amount > 0 do
    spell = %Spell{
      id: 6940,
      name: "Blessing of Sacrifice",
      school: school,
      effects: [
        %Spell.Effect{index: 0, type: :school_damage, base_points: amount, implicit_target_a: :target_enemy}
      ]
    }

    context = %CastContext{
      caster_guid: source_guid,
      caster_level: 1,
      target_guid: target_guid,
      spell: spell
    }

    Effects.enqueue(entity, Effects.deliver_spell(target_guid, context, spell))
  end

  defp enqueue_redirect(entity, _redirect, _source_guid, _school), do: entity

  defp scale_damage_taken(entity, damage, school) when is_integer(damage) and damage > 0 do
    case Aura.percent_multiplier(entity, :mod_damage_percent_taken, Spell.school_mask(school)) do
      multiplier when multiplier != 1.0 -> max(trunc(damage * multiplier), 0)
      _unchanged -> damage
    end
  end

  defp scale_damage_taken(_entity, damage, _school), do: damage

  defp gain_taken_rage(%Character{object: %{guid: guid}} = entity, damage, source)
       when is_integer(source) and source > 0 and source != guid do
    Resources.gain_attack_rage(entity, damage, :taken)
  end

  defp gain_taken_rage(entity, _damage, _source), do: entity

  def heal(%{unit: %Unit{health: health, max_health: max_health} = unit} = entity, amount)
      when is_number(health) and is_number(amount) and amount > 0 do
    new_health =
      if is_number(max_health) and max_health > 0 do
        min(health + amount, max_health)
      else
        health + amount
      end

    %{entity | unit: %{unit | health: new_health}}
    |> Reactive.sync_health()
    |> mark_broadcast_update()
  end

  def heal(entity, _amount), do: entity

  def restore_mana(%{unit: %Unit{power1: power, max_power1: max_power} = unit} = entity, amount)
      when is_number(power) and is_number(max_power) and max_power > 0 and is_number(amount) and amount > 0 do
    %{entity | unit: %{unit | power1: min(power + amount, max_power)}}
    |> mark_broadcast_update()
  end

  def restore_mana(entity, _amount), do: entity

  def dead?(%{unit: %Unit{health: health}}) when is_number(health) do
    health <= 0
  end

  def dead?(_entity), do: false

  def health_pct(%{unit: %Unit{health: health, max_health: max_health}})
      when is_number(health) and is_number(max_health) and max_health > 0 do
    health
    |> max(0)
    |> Kernel./(max_health)
    |> Kernel.*(100)
    |> trunc()
  end

  def health_pct(_entity), do: 100

  def mark_broadcast_update(%{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | broadcast_update?: true}}
  end

  def mark_broadcast_update(entity), do: entity

  def tether_range(%{internal: %Internal{creature: %Creature{leash_range: leash_range}}})
      when is_number(leash_range) and leash_range > 0 do
    leash_range
  end

  def tether_range(%{unit: %Unit{level: level}}) when is_number(level) do
    40 + 2 * level
  end

  def tether_range(_entity) do
    nil
  end

  def out_of_tether_range?(
        %{
          internal: %Internal{spawn: %Spawn{position: {xi, yi, zi}}},
          movement_block: %MovementBlock{position: {x, y, z, _}}
        } = entity
      ) do
    case tether_range(entity) do
      range when is_number(range) ->
        Math.distance({xi, yi, zi}, {x, y, z}) > range

      _ ->
        false
    end
  end

  def out_of_tether_range?(_entity) do
    false
  end

  def should_tether?(%{internal: %Internal{last_hostile_time: last_hostile_time}} = entity, now)
      when is_integer(last_hostile_time) and is_integer(now) do
    out_of_tether_range?(entity) and
      (hard_leash?(entity) or
         (threat_area_limited?(entity) and now - last_hostile_time >= @leash_timeout_ms))
  end

  def should_tether?(_entity, _now) do
    false
  end

  defp hard_leash?(%{internal: %Internal{creature: %Creature{leash_range: leash_range}}})
       when is_number(leash_range) and leash_range > 0 do
    true
  end

  defp hard_leash?(_entity), do: false

  defp threat_area_limited?(%{internal: %Internal{world: %WorldRef{} = world}} = entity) do
    WorldRef.open?(world) and not no_leash_evade?(entity)
  end

  defp threat_area_limited?(entity), do: not no_leash_evade?(entity)

  defp no_leash_evade?(%{internal: %Internal{creature: %Creature{extra_flags: extra_flags}}})
       when is_integer(extra_flags) do
    (extra_flags &&& @extra_flag_no_leash_evade) != 0
  end

  defp no_leash_evade?(_entity), do: false

  defp maybe_dead(%{internal: %Internal{}, unit: %Unit{health: 0}, movement_block: %MovementBlock{}} = entity, now) do
    prepare_death_state(entity, now)
  end

  defp maybe_dead(entity, _now), do: entity

  defp prepare_death_state(%{internal: %Internal{}, unit: %Unit{}, movement_block: %MovementBlock{}} = entity, now) do
    entity = Movement.sync_position(entity, now)
    entity = clear_death_engagement(entity)
    %{unit: unit, movement_block: mb} = entity

    {entity, aura_events} =
      Aura.transition(
        entity,
        %Aura.Change{holders: death_auras(unit.auras), cause: :death, now: now}
      )

    entity = Effects.enqueue(entity, aura_events)
    internal = entity.internal
    unit = entity.unit

    internal = %{
      internal
      | running: false,
        movement_start_time: nil,
        movement_start_position: nil
    }

    movement_block = %{
      mb
      | movement_flags: 0,
        spline_nodes: [],
        spline_flags: 0,
        spline_id: nil,
        spline_start_position: nil,
        time_passed: mb.duration || 0
    }

    %{entity | unit: unit, internal: internal, movement_block: movement_block}
    |> maybe_release_companion()
    |> Combat.sync_combat_flag()
  end

  defp clear_death_engagement(%Mob{} = entity) do
    %Engagement.Result{entity: entity} = Engagement.die(entity)
    entity
  end

  defp clear_death_engagement(%Character{} = entity) do
    {entity, effects} = PlayerCombat.disengage(entity)
    Effects.enqueue(entity, effects)
  end

  defp clear_death_engagement(%{internal: %Internal{} = internal, unit: %Unit{} = unit} = entity) do
    %{entity | unit: %{unit | target: 0}, internal: %{internal | in_combat: false}}
  end

  defp maybe_release_companion(%{player: _player} = entity) do
    {entity, effects} = Companion.dismiss(entity, :owner_died)
    Effects.enqueue(entity, effects)
  end

  defp maybe_release_companion(entity), do: entity

  defp spirit_damage_immune?(entity, opts) do
    Keyword.get(opts, :spell_id) != @spirit_of_redemption_suicide and holder_spell?(entity, @spirit_of_redemption_form)
  end

  defp maybe_enter_spirit_of_redemption(
         %{player: _player, object: %{guid: guid}, unit: %Unit{}, internal: %Internal{}} = entity,
         health,
         new_health,
         now,
         opts
       )
       when is_number(health) and health > 0 and new_health <= 0 and is_integer(guid) do
    if start_spirit_of_redemption?(entity, opts),
      do: enter_spirit_of_redemption(entity, guid, now),
      else: entity
  end

  defp maybe_enter_spirit_of_redemption(entity, _health, _new_health, _now, _opts), do: entity

  defp start_spirit_of_redemption?(entity, opts) do
    Keyword.get(opts, :spell_id) != @spirit_of_redemption_suicide and
      holder_spell?(entity, @spirit_of_redemption_talent)
  end

  defp enter_spirit_of_redemption(%{unit: %Unit{} = unit, internal: %Internal{}} = entity, guid, now) do
    unit = %{
      unit
      | health: max(unit.max_health || 1, 1),
        power1: max(unit.max_power1 || 0, 0)
    }

    entity =
      %{entity | unit: unit}
      |> prepare_death_state(now)

    entity = %{entity | internal: %{entity.internal | rooted?: true}}

    events =
      Enum.map(@spirit_of_redemption_auras, &spirit_of_redemption_event(&1, guid, unit))

    Effects.enqueue(entity, events)
  end

  defp spirit_of_redemption_event(@spirit_of_redemption_form, guid, %Unit{} = unit) do
    Effects.trigger_spell(guid, unit.level || 1, guid, @spirit_of_redemption_form,
      base_points: unit.max_health,
      effect_index: 0,
      duration_ms: @spirit_of_redemption_duration_ms
    )
  end

  defp spirit_of_redemption_event(spell_id, guid, %Unit{} = unit) do
    Effects.trigger_spell(guid, unit.level || 1, guid, spell_id, duration_ms: @spirit_of_redemption_duration_ms)
  end

  defp holder_spell?(%{unit: %Unit{auras: holders}}, spell_id) when is_list(holders) do
    Enum.any?(holders, &match?(%{spell: %Spell{id: ^spell_id}}, &1))
  end

  defp holder_spell?(_entity, _spell_id), do: false

  defp death_auras(holders) when is_list(holders) do
    Enum.filter(holders, fn
      %{spell: %Spell{} = spell} -> Spell.attribute?(spell, :passive)
      _holder -> false
    end)
  end

  defp death_auras(_holders), do: []

  defp maybe_enqueue_death_root(%{player: _player} = entity, health, new_health)
       when is_number(health) and health > 0 and new_health <= 0 do
    Effects.enqueue(entity, Effects.movement_root_changed(true))
  end

  defp maybe_enqueue_death_root(entity, _health, _new_health), do: entity

  defp maybe_prepare_self_res(%{player: player, internal: %Internal{spellbook: spellbook}} = entity, health, new_health)
       when is_number(health) and health > 0 and new_health <= 0 and is_map(spellbook) do
    self_res_spell = if Map.has_key?(spellbook, 20_608), do: 21_169, else: 0
    %{entity | player: %{player | self_res_spell: self_res_spell}}
  end

  defp maybe_prepare_self_res(entity, _health, _new_health), do: entity

  defp maybe_record_killer(%{internal: %Internal{} = internal} = entity, health, new_health, source)
       when is_number(health) and health > 0 and new_health <= 0 and is_integer(source) and source > 0 do
    %{entity | internal: %{internal | killed_by: source}}
  end

  defp maybe_record_killer(entity, _health, _new_health, _source), do: entity
end
