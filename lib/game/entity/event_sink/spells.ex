defmodule ThistleTea.Game.Entity.EventSink.Spells do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Projectile
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SingleTargetAuras
  alias ThistleTea.Game.World.SpellMagnets

  @spell_hit_type_crit 0x2

  def emit(entity, %Effects.SpellPowerDrain{} = effect, _context) do
    %Message.SmsgSpelllogexecute{
      caster: effect.source_guid,
      spell_id: effect.spell_id,
      logs: [{:power_drain, effect.target_guid, effect.amount, effect.power_type, effect.multiplier}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.LeechPower{source_guid: guid} = effect, context) do
    Context.cast(context, {:leech_power, effect})
    entity
  end

  def emit(entity, %Effects.LeechPower{} = effect, _context) do
    Entity.leech_power(effect.source_guid, effect)
    entity
  end

  def emit(entity, %Effects.AddThreat{} = effect, _context) do
    if Guid.entity_type(effect.target_guid) == :mob do
      Entity.add_threat(effect.target_guid, effect)
    end

    entity
  end

  def emit(entity, %Effects.SpellEnergize{} = effect, _context) do
    %Message.SmsgSpellenergizelog{
      caster: effect.source_guid,
      target: effect.target_guid,
      spell_id: effect.spell_id,
      power_type: effect.power_type,
      amount: effect.amount
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellInterrupted{} = effect, _context) do
    %Message.SmsgSpelllogexecute{
      caster: effect.source_guid,
      spell_id: effect.spell_id,
      logs: [{:interrupt_cast, effect.target_guid, effect.interrupted_spell_id}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.SpellSchoolLockout{} = effect, context) do
    Context.send_packet(context, %Message.SmsgSpellCooldown{guid: effect.source_guid, cooldowns: effect.cooldowns})
    entity
  end

  def emit(entity, %Effects.SpellSchoolLockout{}, _context), do: entity

  def emit(entity, %Effects.SpellExtraAttacks{} = effect, _context) do
    %Message.SmsgSpelllogexecute{
      caster: effect.source_guid,
      spell_id: effect.spell_id,
      logs: [{:extra_attacks, effect.target_guid, effect.count}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.TeachSpell{} = effect, context) do
    Context.send(context, {:teach_spell, effect})
    entity
  end

  def emit(entity, %Effects.TeachSpell{}, _context), do: entity

  def emit(entity, %Effects.SpellMagnetsChanged{magnets: magnets}, %Context{owner_pid: owner}) do
    SpellMagnets.sync(entity.object.guid, owner, magnets)
    entity
  end

  def emit(entity, %Effects.SpellMagnetsChanged{}, nil), do: entity

  def emit(entity, %Effects.SingleTargetAurasChanged{claims: claims}, %Context{owner_pid: owner}) do
    SingleTargetAuras.sync(entity.object.guid, owner, entity.internal.world, claims)
    entity
  end

  def emit(entity, %Effects.SingleTargetAurasLeft{}, %Context{owner_pid: owner}) do
    SingleTargetAuras.leave(entity.object.guid, owner)
    entity
  end

  def emit(entity, %Effects.SingleTargetCasterDied{}, %Context{owner_pid: owner}) do
    SingleTargetAuras.caster_died(entity.object.guid, owner)
    entity
  end

  def emit(entity, %Effects.SingleTargetAurasChanged{}, nil), do: entity
  def emit(entity, %Effects.SingleTargetAurasLeft{}, nil), do: entity
  def emit(entity, %Effects.SingleTargetCasterDied{}, nil), do: entity

  def emit(entity, %Effects.DispelFailed{} = effect, _context) do
    %Message.SmsgDispelFailed{
      caster: effect.source_guid,
      target: effect.target_guid,
      spells: effect.spell_ids
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellDispel{} = effect, _context) do
    %Message.SmsgSpelldispellog{
      caster: effect.source_guid,
      victim: effect.target_guid,
      spells: effect.spell_ids
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellDamageImmune{} = effect, _context) do
    %Message.SmsgSpellordamageImmune{
      caster: effect.source_guid,
      target: effect.target_guid,
      spell_id: effect.spell_id
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellDamage{} = effect, _context) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: effect.source_guid || 0,
      target: effect.target_guid,
      spell_id: effect.spell_id,
      damage: max(effect.damage - (effect.absorbed || 0), 0),
      school: Spell.school_index(effect.school),
      periodic?: effect.periodic?,
      absorbed: effect.absorbed || 0,
      resisted: effect.resisted || 0,
      blocked: effect.blocked || 0,
      hit_info: if(effect.crit?, do: @spell_hit_type_crit, else: 0)
    }
    |> World.broadcast_packet(entity)

    notify_spell_outcome(effect)

    entity
  end

  def emit(entity, %Effects.SpellHeal{} = effect, _context) do
    if !effect.periodic? do
      %Message.SmsgSpellheallog{
        target: effect.target_guid,
        caster: effect.source_guid,
        spell_id: effect.spell_id,
        amount: effect.damage,
        critical?: effect.crit?
      }
      |> World.broadcast_packet(entity)
    end

    notify_spell_outcome(effect)
    entity
  end

  def emit(entity, %Effects.SpellLogMiss{} = effect, _context) do
    %Message.SmsgSpellLogMiss{
      spell_id: effect.spell_id,
      caster: effect.source_guid,
      targets: [{effect.target_guid, effect.reason}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.PeriodicAuraLog{} = effect, _context) do
    %Message.SmsgPeriodicauralog{
      target: effect.target_guid,
      caster: effect.source_guid || effect.target_guid,
      spell_id: effect.spell_id,
      auras: [
        %{
          aura_type: effect.aura_type,
          amount: effect.amount || 0,
          misc_value: effect.misc_value || 0,
          multiplier: effect.multiplier
        }
      ]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.AuraDuration{} = effect, context) do
    Context.send_packet(context, %Message.SmsgUpdateAuraDuration{
      aura_slot: effect.aura_slot,
      duration_ms: effect.duration_ms
    })

    entity
  end

  def emit(entity, %Effects.AuraDuration{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ResurrectRequest{} = effect, context) do
    Context.send_packet(context, %Message.SmsgResurrectRequest{guid: effect.source_guid, delayed?: effect.delayed?})
    entity
  end

  def emit(entity, %Effects.ResurrectRequest{}, _context), do: entity

  def emit(entity, %Effects.HealEntity{} = effect, _context) do
    Entity.receive_heal(effect.target_guid, effect)
    entity
  end

  def emit(entity, %Effects.DeliverHealThreat{} = effect, _context) do
    Entity.heal_threat(effect.mob_guid, effect.source_guid, effect.target_guid, effect.amount)
    entity
  end

  def emit(%Character{} = entity, %Effects.SpellCastResult{spell_id: spell_id}, context) do
    Context.send_packet(context, %Message.SmsgCastResult{
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

  def emit(entity, %Effects.SpellCastResult{}, _context), do: entity

  def emit(entity, %Effects.CastRequirementsResolved{cast: cast, requirements: requirements, now: now}, context) do
    entity
    |> Casting.resolve_requirements(cast, requirements, now)
    |> EventSink.emit_pending(context)
  end

  def emit(entity, %Effects.StartTriggeredChannel{} = effect, context) do
    entity
    |> Casting.start_triggered(effect.spell, effect.targets, Time.now(), effect.cast_item_guid, effect.context)
    |> EventSink.emit_pending(context)
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = effect, context) do
    result = %{
      Message.SmsgCastResult.failure(effect.spell_id, effect.reason)
      | required_spell_focus: effect.required_focus_id,
        area: effect.required_area,
        equipped_item_class: effect.equipped_item_class,
        equipped_item_subclass_mask: effect.equipped_item_subclass_mask
    }

    Context.send_packet(context, result)

    Context.send_packet(context, %Message.SmsgSpellFailure{
      guid: guid,
      spell: effect.spell_id,
      result: Message.SmsgCastResult.reason_code(effect.reason)
    })

    %Message.SmsgSpellFailedOther{caster: guid, id: effect.spell_id}
    |> World.broadcast_packet(entity, exclude_self?: true)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = effect, _context) do
    %Message.SmsgSpellFailedOther{caster: guid, id: effect.spell_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellStart{} = effect, _context) when is_integer(guid) do
    packed_caster = BinaryUtils.pack_guid(effect.source_guid || guid)
    projectile = Projectile.fields(entity, effect.spell_id)

    %Message.SmsgSpellStart{
      cast_item: packed_caster,
      caster: packed_caster,
      spell: effect.spell_id,
      flags: Bitwise.bor(0x2, projectile.flags),
      timer: effect.duration_ms || 0,
      targets: effect.targets,
      ammo_display_id: projectile.display_id,
      ammo_inventory_type: projectile.inventory_type
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellStart{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.SpellCooldown{} = effect, context) do
    Context.send_packet(context, %Message.SmsgSpellCooldown{
      guid: effect.source_guid,
      cooldowns: [{effect.spell_id, effect.duration_ms}]
    })

    entity
  end

  def emit(entity, %Effects.SpellCooldown{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :flat} = effect, context) do
    Context.send_packet(context, %Message.SmsgSetFlatSpellModifier{
      effect_index: effect.effect_index,
      operation: effect.operation,
      value: effect.amount
    })

    entity
  end

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :pct} = effect, context) do
    Context.send_packet(context, %Message.SmsgSetPctSpellModifier{
      effect_index: effect.effect_index,
      operation: effect.operation,
      value: effect.amount
    })

    entity
  end

  def emit(entity, %Effects.SpellModifier{}, _context), do: entity

  def emit(entity, %Effects.PetSpellModifiers{} = effect, _context) do
    Entity.sync_pet_spell_modifiers(effect.target_guid, effect.source_guid, effect.holders)
    entity
  end

  def emit(%Character{} = entity, %Effects.CooldownEvent{} = effect, context) do
    Context.send_packet(context, %Message.SmsgCooldownEvent{spell_id: effect.spell_id, guid: effect.source_guid})
    entity
  end

  def emit(entity, %Effects.CooldownEvent{}, _context), do: entity

  def emit(entity, %Effects.ActivateCooldown{target_guid: guid} = effect, context) do
    if entity.object.guid == guid do
      Context.send(context, effect)
    else
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, effect)
        _ -> :ok
      end
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.ClearCooldown{} = effect, context) do
    Context.send_packet(context, %Message.SmsgClearCooldown{
      spell_id: effect.spell_id,
      target_guid: effect.target_guid
    })

    case List.keyfind(Cooldowns.school_cooldowns(entity, Time.now()), effect.spell_id, 0) do
      nil ->
        :ok

      cooldown ->
        Context.send_packet(context, %Message.SmsgSpellCooldown{guid: effect.target_guid, cooldowns: [cooldown]})
    end

    entity
  end

  def emit(entity, %Effects.ClearCooldown{}, _context), do: entity

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellGo{} = effect, _context) when is_integer(guid) do
    projectile = effect.projectile || Projectile.fields(entity, effect.spell_id)

    %Message.SmsgSpellGo{
      cast_item: effect.cast_item_guid || effect.source_guid || guid,
      caster: effect.source_guid || guid,
      spell: effect.spell_id,
      flags: Bitwise.bor(0x100, projectile.flags),
      hits: effect.hit_guids || [],
      misses: effect.misses || [],
      targets: effect.targets,
      ammo_display_id: projectile.display_id,
      ammo_inventory_type: projectile.inventory_type
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellGo{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.StandState{} = effect, context) do
    Context.send_packet(context, %Message.SmsgStandstateUpdate{stand_state: effect.stand_state})
    entity
  end

  def emit(entity, %Effects.StandState{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ChannelStart{} = effect, context) do
    Context.send_packet(context, %Message.MsgChannelStart{
      spell_id: effect.spell_id,
      duration_ms: effect.channel_time_ms
    })

    entity
  end

  def emit(entity, %Effects.ChannelStart{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ChannelUpdate{} = effect, context) do
    Context.send_packet(context, %Message.MsgChannelUpdate{time_ms: effect.channel_time_ms})
    entity
  end

  def emit(entity, %Effects.ChannelUpdate{}, _context), do: entity

  def emit(entity, %Effects.DeliverSpell{} = effect, context) do
    case effect.delay_ms do
      delay_ms when is_integer(delay_ms) and delay_ms > 0 ->
        Context.send_after(context, {:deliver_spell, effect}, delay_ms)

      _ ->
        deliver_spell(effect)
    end

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellContact{target_guid: guid} = effect, context) do
    Context.cast(context, {:spell_contact, effect})
    entity
  end

  def emit(entity, %Effects.SpellContact{} = effect, _context) do
    Entity.spell_contact(effect.target_guid, effect)
    entity
  end

  def emit(entity, %Effects.RemoveAura{} = effect, _context) do
    Entity.remove_aura(effect.target_guid, effect.spell_id, effect.source_guid)
    entity
  end

  def emit(entity, %Effects.DrainPower{target_guid: target_guid, misc_value: power_type}, _context) do
    if Guid.entity_type(target_guid) == :player do
      Entity.drain_power(target_guid, power_type)
    end

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.GrantPower{target_guid: guid} = effect, context) do
    Context.cast(context, {:grant_power, effect})
    entity
  end

  def emit(entity, %Effects.GrantPower{} = effect, _context) do
    Entity.grant_power(effect.target_guid, effect)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.AddComboPoints{source_guid: guid} = effect, context) do
    Context.cast(context, {:add_combo_points, effect})
    entity
  end

  def emit(entity, %Effects.AddComboPoints{} = effect, _context) do
    Entity.add_combo_points(effect.source_guid, effect)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellDelayed{} = effect, context) do
    Context.send_packet(context, %Message.SmsgSpellDelayed{caster: guid, delay_ms: effect.delay_ms})
    entity
  end

  def emit(entity, %Effects.SpellDelayed{}, _context), do: entity

  def emit(entity, %Effects.DelayAura{target_guid: target_guid} = effect, _context)
      when is_integer(target_guid) and target_guid > 0 do
    Entity.delay_aura(target_guid, effect.spell_id, effect.source_guid, effect.delay_ms)
    entity
  end

  def emit(entity, %Effects.DelayAura{}, _context), do: entity

  def emit(entity, %Effects.TriggerSpellRequest{} = effect, _context) do
    Entity.trigger_spell(effect.source_guid, effect.spell_id, effect.target_guid, effect.opts)
    entity
  end

  def emit(%Character{} = entity, %Effects.ScriptedCast{} = effect, context) do
    Context.send(context, {:scripted_cast, effect.entry, effect.target_guid})
    entity
  end

  def emit(%Character{} = entity, %Effects.CharmCast{} = effect, context) do
    Context.send(context, {:charm_cast, effect})
    entity
  end

  def deliver_spell(%Effects.DeliverSpell{} = effect) do
    Entity.receive_spell(effect.target_guid, effect.cast_context, effect.spell)
  end

  defp notify_spell_outcome(%Effects.SpellDamage{} = effect) do
    notify_spell_outcome(effect, effect.absorbed)
  end

  defp notify_spell_outcome(%Effects.SpellHeal{} = effect) do
    notify_spell_outcome(effect, 0)
  end

  defp notify_spell_outcome(
         %{source_guid: source_guid, target_guid: target_guid, proc_type: proc_type} = effect,
         absorbed
       )
       when is_integer(source_guid) and is_atom(proc_type) and not is_nil(proc_type) do
    Entity.spell_outcome(source_guid, %{
      victim_guid: target_guid,
      outcome: if(effect.crit?, do: :crit, else: :normal),
      damage: max((effect.damage || 0) - (absorbed || 0), 0),
      proc_type: proc_type,
      spell_id: effect.spell_id
    })
  end

  defp notify_spell_outcome(_effect, _absorbed), do: :ok
end
