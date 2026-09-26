defmodule ThistleTea.Game.Entity.Logic.Core do
  @moduledoc """
  Entity operations generic across all entity types: building update-object
  payloads, taking damage and dying, healing, mana restoration, and combat
  tether-range checks for mobs.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CastPushback
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.CorpseReclaim
  alias ThistleTea.Game.Entity.Logic.Critter
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.DamageOrigin
  alias ThistleTea.Game.Entity.Logic.DamageSharing
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.Durability
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Honor.Combat, as: HonorCombat
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.KillCredit
  alias ThistleTea.Game.Entity.Logic.KillFeedback
  alias ThistleTea.Game.Entity.Logic.MiniPet
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SelfResurrection
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Combat, as: SpellCombat

  @spirit_of_redemption_talent 20_711
  @spirit_of_redemption_form 27_827
  @spirit_of_redemption_auras [27_827, 27_792, 27_795]
  @spirit_of_redemption_suicide 27_965
  @spirit_of_redemption_duration_ms 15_000

  def update_object(entity, update_type \\ :create_object2)

  def update_object(%Mob{} = entity, update_type) do
    entity = %{entity | unit: %{entity.unit | target: Assistance.visible_target(entity)}}
    update_object(entity, update_type, :unit)
  end

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

  def kill(%Mob{} = entity, now) when is_integer(now) do
    if dead?(entity) do
      entity
    else
      entity = DamageOrigin.record(entity, entity.unit.health, entity.unit.health, source: entity.object.guid)

      %{entity | unit: %{entity.unit | health: 0}, internal: %{entity.internal | killed_by: entity.object.guid}}
      |> sync_health()
      |> prepare_death_state(now)
      |> mark_broadcast_update()
    end
  end

  def take_damage_with_absorb(entity, damage, now, opts \\ []) do
    {entity, _damage, absorbed} = take_damage_with_mitigation(entity, damage, now, opts)
    {entity, absorbed}
  end

  @doc "Returns the updated entity, damage after received modifiers, and damage prevented by absorption and sharing."
  def take_damage_with_mitigation(entity, damage, now, opts \\ [])

  def take_damage_with_mitigation(%{internal: %Internal{godmode: true}} = entity, _damage, _now, _opts),
    do: {entity, 0, 0}

  def take_damage_with_mitigation(entity, damage, now, opts)
      when is_number(damage) and damage > 0 and is_integer(now) do
    if Keyword.get(opts, :shared_damage) != :unmitigated and
         DamageImmunity.immune?(entity, Keyword.get(opts, :school, :physical), Keyword.get(opts, :spell)) do
      {entity, damage, damage}
    else
      take_unblocked_damage(entity, damage, now, opts)
    end
  end

  def take_damage_with_mitigation(entity, _damage, _now, _opts), do: {entity, 0, 0}

  defp take_unblocked_damage(%{unit: %Unit{health: health}} = entity, damage, now, opts) do
    if spirit_damage_immune?(entity, opts) do
      {entity, damage, damage}
    else
      entity = enter_damage_combat(entity, now, opts)
      entity = CombatLeash.on_damage(entity, now, opts)
      school = Keyword.get(opts, :school, :physical)
      {entity, damage, remaining} = mitigate_damage(entity, damage, school, now, opts)
      entity = DamageOrigin.record(entity, health, remaining, opts)
      damage_threat = remaining * Keyword.get(opts, :threat_multiplier, 1.0)
      %{unit: unit} = entity
      duel_outcome = duel_lethal_outcome(entity, health, remaining, opts)
      remaining = duel_remaining_damage(health, remaining, duel_outcome)
      remaining = invincibility_remaining_damage(entity, health, remaining)
      absorbed = damage - remaining
      new_health = max(health - remaining, 0)

      entity = %{entity | unit: %{unit | health: new_health}}
      entity = enqueue_duel_outcome(entity, duel_outcome)
      entity = Aura.enqueue_death_item_rewards(entity, health, new_health)
      entity = KillFeedback.capture(entity, health, new_health, Keyword.get(opts, :source))
      entity = HonorCombat.on_damage(entity, health, remaining, new_health, now, opts)
      entity = maybe_enqueue_defeat(entity, health, new_health, opts)

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
        |> sync_health()
        |> Threat.add_damage(Keyword.get(opts, :source), damage_threat)
        |> Durability.on_damage(health, remaining, new_health, opts)
        |> maybe_enqueue_death_root(health, new_health)
        |> maybe_prepare_self_res(health, new_health, now)
        |> maybe_record_killer(health, new_health, Keyword.get(opts, :source))
        |> maybe_enter_spirit_of_redemption(health, new_health, now, opts)
        |> CorpseReclaim.on_damage(health, now)
        |> mark_broadcast_update()
        |> maybe_dead(now)
        |> Critter.react(Keyword.get(opts, :source), now)

      {entity, damage, absorbed}
    end
  end

  defp take_unblocked_damage(entity, _damage, _now, _opts), do: {entity, 0, 0}

  defp enter_damage_combat(entity, now, opts) do
    if SpellCombat.damage_contact?(
         Keyword.get(opts, :spell),
         Keyword.get(opts, :periodic, false),
         Keyword.get(opts, :triggered_by_proc?, false)
       ) do
      source = Keyword.get(opts, :source)

      entity
      |> PlayerCombat.mark_hostile_contact(source, now)
      |> Engagement.on_damage(source, now)
    else
      entity
    end
  end

  defp mitigate_damage(entity, damage, school, now, opts) do
    cond do
      Keyword.get(opts, :environmental?, false) or Keyword.get(opts, :shared_damage) == :unmitigated ->
        {entity, damage, damage}

      Keyword.get(opts, :shared_damage) == :absorb ->
        {entity, remaining} = Aura.absorb_damage(entity, damage, school, now)
        {entity, damage, remaining}

      true ->
        damage = scale_damage_taken(entity, damage, school)
        {entity, remaining} = Aura.absorb_damage(entity, damage, school, now)
        {remaining, transfers} = DamageSharing.split(entity, remaining, school, now, opts)
        {Effects.enqueue(entity, transfers), damage, remaining}
    end
  end

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
    |> sync_health()
    |> mark_broadcast_update()
  end

  def heal(entity, _amount), do: entity

  defp sync_health(entity) do
    {entity, events} = entity |> Reactive.sync_health() |> MovementStats.sync()
    Effects.enqueue(entity, events)
  end

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

  def health_deficit(%{unit: %Unit{health: health, max_health: maximum}})
      when is_integer(health) and is_integer(maximum), do: max(maximum - health, 0)

  def health_deficit(_entity), do: 0

  def mana_pct(%{unit: %Unit{power1: mana, max_power1: max_mana}})
      when is_number(mana) and is_number(max_mana) and max_mana > 0 do
    mana
    |> max(0)
    |> Kernel./(max_mana)
    |> Kernel.*(100)
    |> trunc()
  end

  def mana_pct(_entity), do: nil

  def mark_broadcast_update(%{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | broadcast_update?: true}}
  end

  def mark_broadcast_update(entity), do: entity

  def tether_range(entity), do: CombatLeash.range(entity)

  def out_of_tether_range?(%{movement_block: %MovementBlock{position: {x, y, z, _}}} = entity) do
    case CombatLeash.origin(entity) do
      {xi, yi, zi} ->
        Math.distance({xi, yi, zi}, {x, y, z}) > tether_range(entity)

      _ ->
        false
    end
  end

  def out_of_tether_range?(_entity) do
    false
  end

  def should_tether?(entity, now, opts \\ []), do: CombatLeash.should_evade?(entity, now, opts)

  defp maybe_dead(%{internal: %Internal{}, unit: %Unit{health: 0}, movement_block: %MovementBlock{}} = entity, now) do
    prepare_death_state(entity, now)
  end

  defp maybe_dead(entity, _now), do: entity

  defp prepare_death_state(%{internal: %Internal{}, unit: %Unit{}, movement_block: %MovementBlock{}} = entity, now) do
    entity = Movement.sync_position(entity, now)
    entity = clear_death_engagement(entity)
    entity = Reactive.clear(entity, now)
    unit = entity.unit

    {entity, aura_events} =
      Aura.transition(
        entity,
        %Aura.Change{holders: death_auras(unit.auras), cause: :death, now: now}
      )

    entity = Effects.enqueue(entity, aura_events ++ [%Effects.SingleTargetCasterDied{}])
    internal = entity.internal
    unit = entity.unit
    mb = entity.movement_block

    internal = %{
      internal
      | running: false,
        fall: nil,
        navigation_intents: [],
        events: Enum.reject(internal.events, &is_struct(&1, Effects.MonsterMove)),
        diminishing_returns: %{},
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
    |> Emote.reset()
    |> Intoxication.clear()
    |> Effects.enqueue(Effects.movement_stopped())
    |> maybe_release_companion()
    |> MiniPet.dismiss()
    |> Totems.dismiss_all()
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

  defp maybe_enqueue_defeat(%Character{} = entity, health, 0, opts) when health > 0 do
    Effects.enqueue(entity, %Effects.PlayerDefeated{
      source_guid: Keyword.get(opts, :source),
      count_death?: !start_spirit_of_redemption?(entity, opts)
    })
  end

  defp maybe_enqueue_defeat(%Mob{} = entity, health, 0, opts) when health > 0 do
    entity
    |> KillCredit.capture()
    |> Effects.enqueue(%Effects.CreatureDefeated{source_guid: Keyword.get(opts, :source)})
  end

  defp maybe_enqueue_defeat(entity, _health, _new_health, _opts), do: entity

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
      %{spell: %Spell{} = spell} -> Spell.attribute?(spell, :passive) or Spell.attribute?(spell, :death_persistent)
      _holder -> false
    end)
  end

  defp death_auras(_holders), do: []

  defp maybe_enqueue_death_root(%{player: _player} = entity, health, new_health)
       when is_number(health) and health > 0 and new_health <= 0 do
    Effects.enqueue(entity, Effects.movement_root_changed(true))
  end

  defp maybe_enqueue_death_root(entity, _health, _new_health), do: entity

  defp maybe_prepare_self_res(entity, health, new_health, now)
       when is_number(health) and health > 0 and new_health <= 0 do
    SelfResurrection.capture(entity, now)
  end

  defp maybe_prepare_self_res(entity, _health, _new_health, _now), do: entity

  defp maybe_record_killer(%{internal: %Internal{} = internal} = entity, health, new_health, source)
       when is_number(health) and health > 0 and new_health <= 0 and is_integer(source) and source > 0 do
    %{entity | internal: %{internal | killed_by: source}}
  end

  defp maybe_record_killer(entity, _health, _new_health, _source), do: entity
end
