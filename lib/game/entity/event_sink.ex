defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Boundary that drains the events queued on an entity by pure logic and
  performs their side effects: building packets, broadcasting to nearby
  players, and messaging other entity processes.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Combat, as: CombatEffects
  alias ThistleTea.Game.Entity.EventSink.Movement, as: MovementEffects
  alias ThistleTea.Game.Entity.EventSink.Summons, as: SummonEffects
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @heal_threat_radius 100.0
  @spell_hit_type_crit 0x2
  @client_effects [
    Effects.ConsumeCastItem,
    Effects.ConsumeReagents,
    Effects.CreateItem,
    Effects.Emote,
    Effects.EnchantItem,
    Effects.FeedPet,
    Effects.ForwardScriptSteps,
    Effects.GiveItem,
    Effects.MonsterTalk,
    Effects.ObjectUpdate,
    Effects.OpenGameObject,
    Effects.PlayObjectSound,
    Effects.PlaySound,
    Effects.ScriptSteps
  ]
  @combat_effects [
    Effects.AttackNotInRange,
    Effects.AttackOutcome,
    Effects.AttackStart,
    Effects.AttackStop,
    Effects.AttackerGained,
    Effects.AttackerLost,
    Effects.AttackerStateUpdate,
    Effects.BladeFlurry,
    Effects.CallAssistance,
    Effects.CallForHelp,
    Effects.DeliverAttack,
    Effects.DropNearbyThreat,
    Effects.DropThreat,
    Effects.DuelDefeat,
    Effects.DuelInterrupted,
    Effects.DuelRequest,
    Effects.SecondaryMelee,
    Effects.StartAttack,
    Effects.TapCleared,
    Effects.ThreatRefGained,
    Effects.ThreatRefLost
  ]
  @movement_effects [
    Effects.Charge,
    Effects.FeatherFallChanged,
    Effects.HoverChanged,
    Effects.Leap,
    Effects.MonsterMove,
    Effects.MovementRootChanged,
    Effects.MovementSpeedChanged,
    Effects.MovementStopped,
    Effects.SetFacing,
    Effects.Teleport,
    Effects.TeleportToSpellTarget,
    Effects.WaterWalkChanged
  ]
  @summon_effects [
    Effects.ControlGranted,
    Effects.ControlReleased,
    Effects.DespawnAreaEffects,
    Effects.DespawnEntity,
    Effects.DespawnSelf,
    Effects.DismissPet,
    Effects.LeaveRitual,
    Effects.ReleaseControlled,
    Effects.SpawnAreaEffect,
    Effects.SpawnFarsight,
    Effects.SummonCreature,
    Effects.SummonGameObject,
    Effects.SummonPet,
    Effects.SummonRequest,
    Effects.SummonTotem,
    Effects.TameCreature,
    Effects.ViewpointGranted,
    Effects.ViewpointReleased
  ]

  def emit_pending(entity) do
    {entity, events} = Effects.drain(entity)
    emit(entity, events)
  end

  def emit(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &emit(&2, &1))
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @client_effects do
    ClientProjection.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @combat_effects do
    CombatEffects.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @movement_effects do
    MovementEffects.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @summon_effects do
    SummonEffects.emit(entity, effect)
  end

  def emit(entity, %Effects.SpellDamage{} = event) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: event.source_guid || 0,
      target: event.target_guid,
      spell_id: event.spell_id,
      damage: event.damage,
      school: Spell.school_index(event.school),
      periodic?: event.periodic?,
      absorbed: event.absorbed || 0,
      resisted: event.resisted || 0,
      blocked: event.blocked || 0,
      hit_info: if(event.crit?, do: @spell_hit_type_crit, else: 0)
    }
    |> World.broadcast_packet(entity)

    notify_spell_outcome(event)

    entity
  end

  def emit(entity, %Effects.SpellHeal{} = event) do
    notify_spell_outcome(event)
    entity
  end

  def emit(entity, %Effects.SpellLogMiss{} = event) do
    %Message.SmsgSpellLogMiss{
      spell_id: event.spell_id,
      caster: event.source_guid,
      targets: [{event.target_guid, event.reason}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.PeriodicAuraLog{} = event) do
    %Message.SmsgPeriodicauralog{
      target: event.target_guid,
      caster: event.source_guid || event.target_guid,
      spell_id: event.spell_id,
      auras: [
        %{
          aura_type: event.aura_type,
          amount: event.amount || 0,
          misc_value: event.misc_value || 0
        }
      ]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.AuraDuration{} = event) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: event.aura_slot,
      duration_ms: event.duration_ms
    })

    entity
  end

  def emit(entity, %Effects.AuraDuration{}), do: entity

  def emit(%Character{} = entity, %Effects.ResurrectRequest{} = event) do
    Network.send_packet(%Message.SmsgResurrectRequest{guid: event.source_guid})
    entity
  end

  def emit(entity, %Effects.ResurrectRequest{}), do: entity

  def emit(entity, %Effects.HealEntity{} = event) do
    Entity.receive_heal(event.target_guid, event.amount)
    entity
  end

  def emit(entity, %Effects.HealThreat{} = event) do
    entity
    |> World.nearby_mobs(@heal_threat_radius)
    |> Enum.each(fn {guid, _distance} ->
      Entity.heal_threat(guid, event.source_guid, event.target_guid, event.amount)
    end)

    entity
  end

  def emit(%Character{} = entity, %Effects.SpellCastResult{spell_id: spell_id}) do
    Network.send_packet(%Message.SmsgCastResult{
      spell: spell_id,
      result: 0,
      reason: nil,
      required_spell_focus: nil,
      area: nil,
      equipped_item_class: nil,
      equipped_item_subclass_mask: nil,
      equipped_item_inventory_type_mask: nil
    })

    entity
  end

  def emit(entity, %Effects.SpellCastResult{}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = event) do
    Network.send_packet(Message.SmsgCastResult.failure(event.spell_id, event.reason))

    Network.send_packet(%Message.SmsgSpellFailure{
      guid: guid,
      spell: event.spell_id,
      result: Message.SmsgCastResult.reason_code(event.reason)
    })

    %Message.SmsgSpellFailedOther{caster: guid, id: event.spell_id}
    |> World.broadcast_packet(entity, exclude_self?: true)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = event) do
    %Message.SmsgSpellFailedOther{caster: guid, id: event.spell_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellStart{} = event) when is_integer(guid) do
    packed_caster = BinaryUtils.pack_guid(event.source_guid || guid)

    %Message.SmsgSpellStart{
      cast_item: packed_caster,
      caster: packed_caster,
      spell: event.spell_id,
      flags: 0x2,
      timer: event.duration_ms || 0,
      targets: event.raw_targets || <<>>,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellStart{}), do: entity

  def emit(%Character{} = entity, %Effects.SpellCooldown{} = event) do
    Network.send_packet(%Message.SmsgSpellCooldown{
      guid: event.source_guid,
      cooldowns: [{event.spell_id, event.duration_ms}]
    })

    entity
  end

  def emit(entity, %Effects.SpellCooldown{}), do: entity

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :flat} = event) do
    Network.send_packet(%Message.SmsgSetFlatSpellModifier{
      effect_index: event.effect_index,
      operation: event.operation,
      value: event.amount
    })

    entity
  end

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :pct} = event) do
    Network.send_packet(%Message.SmsgSetPctSpellModifier{
      effect_index: event.effect_index,
      operation: event.operation,
      value: event.amount
    })

    entity
  end

  def emit(entity, %Effects.SpellModifier{}), do: entity

  def emit(%Character{} = entity, %Effects.CooldownEvent{} = event) do
    Network.send_packet(%Message.SmsgCooldownEvent{spell_id: event.spell_id, guid: event.source_guid})
    entity
  end

  def emit(entity, %Effects.CooldownEvent{}), do: entity

  def emit(%Character{} = entity, %Effects.ClearCooldown{} = event) do
    Network.send_packet(%Message.SmsgClearCooldown{
      spell_id: event.spell_id,
      target_guid: event.target_guid
    })

    entity
  end

  def emit(entity, %Effects.ClearCooldown{}), do: entity

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellGo{} = event) when is_integer(guid) do
    %Message.SmsgSpellGo{
      cast_item: event.cast_item_guid || event.source_guid || guid,
      caster: event.source_guid || guid,
      spell: event.spell_id,
      flags: 0x100,
      hits: event.hit_guids || [],
      misses: event.misses || [],
      targets: event.raw_targets || <<>>,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellGo{}), do: entity

  def emit(%Character{} = entity, %Effects.StandState{} = event) do
    Network.send_packet(%Message.SmsgStandstateUpdate{stand_state: event.stand_state})
    entity
  end

  def emit(entity, %Effects.StandState{}), do: entity

  def emit(%Character{} = entity, %Effects.ChannelStart{} = event) do
    Network.send_packet(%Message.MsgChannelStart{
      spell_id: event.spell_id,
      duration_ms: event.channel_time_ms
    })

    entity
  end

  def emit(entity, %Effects.ChannelStart{}), do: entity

  def emit(%Character{} = entity, %Effects.ChannelUpdate{} = event) do
    Network.send_packet(%Message.MsgChannelUpdate{time_ms: event.channel_time_ms})
    entity
  end

  def emit(entity, %Effects.ChannelUpdate{}), do: entity

  def emit(entity, %Effects.DeliverSpell{} = event) do
    case projectile_delay_ms(entity, event) do
      delay_ms when is_integer(delay_ms) and delay_ms > 0 ->
        Process.send_after(self(), {:deliver_spell, event}, delay_ms)

      _ ->
        deliver_spell(event)
    end

    entity
  end

  def emit(entity, %Effects.DeliverSpellOutcome{} = event) do
    Entity.receive_spell_outcome(event.target_guid, event.source_guid, event.spell, event.outcome)
    entity
  end

  def emit(entity, %Effects.RemoveAura{} = event) do
    Entity.remove_aura(event.target_guid, event.spell_id, event.source_guid)
    entity
  end

  def emit(entity, %Effects.DrainPower{target_guid: target_guid, misc_value: power_type}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.drain_power(target_guid, power_type)
    end

    entity
  end

  def emit(entity, %Effects.GrantPower{} = event) do
    if Guid.entity_type(event.target_guid) == :player do
      Entity.grant_power(event.target_guid, event.misc_value, event.amount)
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.RefreshPartyAura{spell: %Spell{} = spell, amount: radius})
      when is_number(radius) do
    entity
    |> SpellTargetResolver.resolve_query({:party_aoe, radius})
    |> Enum.reject(&(&1 == entity.object.guid))
    |> Enum.each(fn target_guid ->
      context = CastContext.from_caster(entity, spell, target_guid)
      Entity.receive_spell(target_guid, context, spell)
    end)

    entity
  end

  def emit(%Mob{object: %{guid: guid}, internal: %{pet: %{owner_guid: owner_guid}}} = entity, %Effects.RefreshPartyAura{
        spell: %Spell{} = spell
      }) do
    context = %CastContext{
      caster_guid: guid,
      caster_level: entity.unit.level || 1,
      target_guid: owner_guid,
      target_hostile?: false,
      spell: spell
    }

    Entity.receive_spell(owner_guid, context, spell)
    entity
  end

  def emit(%Mob{object: %{guid: guid}, unit: %{created_by: owner_guid}} = entity, %Effects.RefreshPartyAura{
        spell: %Spell{} = spell,
        amount: radius
      })
      when is_integer(owner_guid) and owner_guid > 0 and is_number(radius) do
    entity
    |> SpellTargetResolver.resolve_query({:party_aoe, radius})
    |> Enum.each(fn target_guid ->
      context = %CastContext{
        caster_guid: guid,
        caster_level: entity.unit.level || 1,
        target_guid: target_guid,
        target_hostile?: false,
        spell: spell
      }

      Entity.receive_spell(target_guid, context, spell)
    end)

    entity
  end

  def emit(entity, %Effects.RefreshPartyAura{}), do: entity

  def emit(entity, %Effects.RedirectDamage{} = event) do
    spell = %Spell{
      id: 6940,
      name: "Blessing of Sacrifice",
      school: event.school,
      effects: [
        %Spell.Effect{index: 0, type: :school_damage, base_points: event.amount, implicit_target_a: :target_enemy}
      ]
    }

    context = %CastContext{
      caster_guid: event.source_guid,
      caster_level: 1,
      target_guid: event.target_guid,
      spell: spell
    }

    Entity.receive_spell(event.target_guid, context, spell)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellDelayed{} = event) do
    Network.send_packet(%Message.SmsgSpellDelayed{caster: guid, delay_ms: event.delay_ms})
    entity
  end

  def emit(entity, %Effects.SpellDelayed{}), do: entity

  def emit(entity, %Effects.DelayAura{target_guid: target_guid} = event)
      when is_integer(target_guid) and target_guid > 0 do
    Entity.delay_aura(target_guid, event.spell_id, event.source_guid, event.delay_ms)
    entity
  end

  def emit(entity, %Effects.DelayAura{}), do: entity

  def emit(
        %{object: %{guid: guid}} = entity,
        %Effects.TriggerSpell{source_guid: source, resolve_targets?: true} = event
      )
      when is_integer(source) and source != guid do
    Entity.trigger_spell(source, event.spell_id, event.target_guid,
      base_points: event.amount,
      effect_index: event.slot,
      resolve_targets?: true,
      triggered_by_spell_id: event.triggering_spell_id
    )

    entity
  end

  def emit(entity, %Effects.TriggerSpell{} = event) do
    case SpellLoader.load(event.spell_id) do
      nil ->
        entity

      spell ->
        spell = scripted_proc_spell(spell, event)
        spell = apply_trigger_override(spell, event)
        dispatch_trigger_event(entity, event, spell)
    end
  end

  def emit(entity, _event), do: entity

  defp notify_spell_outcome(%Effects.SpellDamage{} = event) do
    notify_spell_outcome(event, event.absorbed)
  end

  defp notify_spell_outcome(%Effects.SpellHeal{} = event) do
    notify_spell_outcome(event, 0)
  end

  defp notify_spell_outcome(
         %{source_guid: source_guid, target_guid: target_guid, proc_type: proc_type} = event,
         absorbed
       )
       when is_integer(source_guid) and is_atom(proc_type) do
    Entity.spell_outcome(source_guid, %{
      victim_guid: target_guid,
      outcome: if(event.crit?, do: :crit, else: :normal),
      damage: max((event.damage || 0) - (absorbed || 0), 0),
      proc_type: proc_type,
      spell_id: event.spell_id
    })
  end

  defp notify_spell_outcome(_event, _absorbed), do: :ok

  defp scripted_proc_spell(%Spell{} = spell, %Effects.TriggerSpell{triggering_spell_id: triggering_spell_id}) do
    case Scripts.proc_trigger_spell_id(spell, triggering_spell_id) do
      spell_id when spell_id == spell.id -> spell
      spell_id when is_integer(spell_id) -> SpellLoader.load(spell_id)
      _missing -> nil
    end
  end

  defp dispatch_trigger_event(entity, event, %Spell{} = spell) do
    if event.resolve_targets? or SpellTarget.area_targeted?(spell) do
      dispatch_resolved_trigger(entity, event, spell)
    else
      dispatch_single_trigger(entity, event, spell)
    end
  end

  defp dispatch_trigger_event(entity, _event, _spell), do: entity

  defp dispatch_single_trigger(entity, event, spell) do
    case triggered_target(entity, event, spell) do
      nil ->
        entity

      target_guid ->
        event = %{event | target_guid: target_guid}

        entity
        |> emit(
          Effects.spell_go(
            event.source_guid || entity.object.guid,
            event.spell_id,
            [target_guid],
            Targets.unit(target_guid).raw
          )
        )
        |> dispatch_triggered_spell(event, spell)
    end
  end

  defp dispatch_resolved_trigger(entity, event, spell) do
    targets = SpellTargetResolver.resolve(entity, spell, Targets.unit(event.target_guid))

    entity =
      emit(
        entity,
        Effects.spell_go(
          event.source_guid || entity.object.guid,
          event.spell_id,
          targets,
          Targets.unit(event.target_guid).raw
        )
      )

    Enum.reduce(targets, entity, fn target_guid, current ->
      dispatch_triggered_spell(current, %{event | target_guid: target_guid}, spell)
    end)
  end

  def deliver_spell(%Effects.DeliverSpell{} = event) do
    Entity.receive_spell(event.target_guid, event.cast_context, event.spell)
  end

  defp projectile_delay_ms(%{movement_block: %{position: {x, y, z, _o}}}, %Effects.DeliverSpell{
         spell: %Spell{speed: speed},
         target_guid: target_guid
       })
       when is_number(speed) and speed > 0 and is_integer(target_guid) do
    case World.position(target_guid) do
      {_map, tx, ty, tz} ->
        distance = :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
        trunc(distance / speed * 1000)

      _ ->
        0
    end
  end

  defp projectile_delay_ms(_entity, _event), do: 0

  defp dispatch_triggered_spell(
         %{object: %{guid: guid}} = entity,
         %Effects.TriggerSpell{target_guid: guid} = event,
         spell
       ) do
    context = trigger_context(entity, event, spell)
    {entity, events} = SpellEffect.receive(entity, context, spell, Time.now())
    emit(entity, events)
  end

  defp dispatch_triggered_spell(entity, %Effects.TriggerSpell{} = event, spell) do
    context = trigger_context(entity, event, spell)
    emit(entity, Effects.deliver_spell(event.target_guid, context, spell))
  end

  defp apply_trigger_override(%Spell{} = spell, %Effects.TriggerSpell{} = event) do
    spell
    |> apply_trigger_effect_override(event)
    |> apply_trigger_duration_override(event)
  end

  defp apply_trigger_effect_override(%Spell{effects: effects} = spell, %Effects.TriggerSpell{
         slot: index,
         amount: amount
       })
       when is_integer(index) and is_integer(amount) do
    effects =
      Enum.map(effects, fn
        %Spell.Effect{index: ^index} = effect -> %{effect | base_points: amount, die_sides: 0, base_dice: 0}
        effect -> effect
      end)

    %{spell | effects: effects}
  end

  defp apply_trigger_effect_override(spell, _event), do: spell

  defp apply_trigger_duration_override(%Spell{} = spell, %Effects.TriggerSpell{duration_ms: duration_ms})
       when is_integer(duration_ms) and duration_ms > 0 do
    %{spell | duration_ms: duration_ms, max_duration_ms: duration_ms}
  end

  defp apply_trigger_duration_override(spell, _event), do: spell

  defp triggered_target(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = event, spell) do
    SpellTarget.redirect_trigger_target(entity, event.target_guid, spell)
  end

  defp triggered_target(_entity, %Effects.TriggerSpell{} = event, _spell), do: event.target_guid

  defp trigger_context(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = event, spell) do
    %{
      CastContext.from_caster(entity, spell, event.target_guid)
      | target_hostile?: Spell.requires_hostile_target?(spell),
        target_role: event.target_role
    }
  end

  defp trigger_context(_entity, %Effects.TriggerSpell{} = event, spell) do
    %CastContext{
      caster_guid: event.source_guid,
      caster_level: event.source_level || 1,
      target_guid: event.target_guid,
      target_role: event.target_role,
      target_hostile?: Spell.requires_hostile_target?(spell),
      spell: spell
    }
  end
end
