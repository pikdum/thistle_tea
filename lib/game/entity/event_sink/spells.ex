defmodule ThistleTea.Game.Entity.EventSink.Spells do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @heal_threat_radius 100.0
  @spell_hit_type_crit 0x2

  def emit(entity, %Effects.SpellDamage{} = effect) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: effect.source_guid || 0,
      target: effect.target_guid,
      spell_id: effect.spell_id,
      damage: effect.damage,
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

  def emit(entity, %Effects.SpellHeal{} = effect) do
    notify_spell_outcome(effect)
    entity
  end

  def emit(entity, %Effects.SpellLogMiss{} = effect) do
    %Message.SmsgSpellLogMiss{
      spell_id: effect.spell_id,
      caster: effect.source_guid,
      targets: [{effect.target_guid, effect.reason}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.PeriodicAuraLog{} = effect) do
    %Message.SmsgPeriodicauralog{
      target: effect.target_guid,
      caster: effect.source_guid || effect.target_guid,
      spell_id: effect.spell_id,
      auras: [
        %{
          aura_type: effect.aura_type,
          amount: effect.amount || 0,
          misc_value: effect.misc_value || 0
        }
      ]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.AuraDuration{} = effect) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: effect.aura_slot,
      duration_ms: effect.duration_ms
    })

    entity
  end

  def emit(entity, %Effects.AuraDuration{}), do: entity

  def emit(%Character{} = entity, %Effects.ResurrectRequest{} = effect) do
    Network.send_packet(%Message.SmsgResurrectRequest{guid: effect.source_guid})
    entity
  end

  def emit(entity, %Effects.ResurrectRequest{}), do: entity

  def emit(entity, %Effects.HealEntity{} = effect) do
    Entity.receive_heal(effect.target_guid, effect.amount)
    entity
  end

  def emit(entity, %Effects.HealThreat{} = effect) do
    entity
    |> World.nearby_mobs(@heal_threat_radius)
    |> Enum.each(fn {guid, _distance} ->
      Entity.heal_threat(guid, effect.source_guid, effect.target_guid, effect.amount)
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

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = effect) do
    Network.send_packet(Message.SmsgCastResult.failure(effect.spell_id, effect.reason))

    Network.send_packet(%Message.SmsgSpellFailure{
      guid: guid,
      spell: effect.spell_id,
      result: Message.SmsgCastResult.reason_code(effect.reason)
    })

    %Message.SmsgSpellFailedOther{caster: guid, id: effect.spell_id}
    |> World.broadcast_packet(entity, exclude_self?: true)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellCastFailed{} = effect) do
    %Message.SmsgSpellFailedOther{caster: guid, id: effect.spell_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellStart{} = effect) when is_integer(guid) do
    packed_caster = BinaryUtils.pack_guid(effect.source_guid || guid)

    %Message.SmsgSpellStart{
      cast_item: packed_caster,
      caster: packed_caster,
      spell: effect.spell_id,
      flags: 0x2,
      timer: effect.duration_ms || 0,
      targets: effect.targets,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellStart{}), do: entity

  def emit(%Character{} = entity, %Effects.SpellCooldown{} = effect) do
    Network.send_packet(%Message.SmsgSpellCooldown{
      guid: effect.source_guid,
      cooldowns: [{effect.spell_id, effect.duration_ms}]
    })

    entity
  end

  def emit(entity, %Effects.SpellCooldown{}), do: entity

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :flat} = effect) do
    Network.send_packet(%Message.SmsgSetFlatSpellModifier{
      effect_index: effect.effect_index,
      operation: effect.operation,
      value: effect.amount
    })

    entity
  end

  def emit(%Character{} = entity, %Effects.SpellModifier{modifier_type: :pct} = effect) do
    Network.send_packet(%Message.SmsgSetPctSpellModifier{
      effect_index: effect.effect_index,
      operation: effect.operation,
      value: effect.amount
    })

    entity
  end

  def emit(entity, %Effects.SpellModifier{}), do: entity

  def emit(%Character{} = entity, %Effects.CooldownEvent{} = effect) do
    Network.send_packet(%Message.SmsgCooldownEvent{spell_id: effect.spell_id, guid: effect.source_guid})
    entity
  end

  def emit(entity, %Effects.CooldownEvent{}), do: entity

  def emit(%Character{} = entity, %Effects.ClearCooldown{} = effect) do
    Network.send_packet(%Message.SmsgClearCooldown{
      spell_id: effect.spell_id,
      target_guid: effect.target_guid
    })

    entity
  end

  def emit(entity, %Effects.ClearCooldown{}), do: entity

  def emit(%{object: %{guid: guid}} = entity, %Effects.SpellGo{} = effect) when is_integer(guid) do
    %Message.SmsgSpellGo{
      cast_item: effect.cast_item_guid || effect.source_guid || guid,
      caster: effect.source_guid || guid,
      spell: effect.spell_id,
      flags: 0x100,
      hits: effect.hit_guids || [],
      misses: effect.misses || [],
      targets: effect.targets,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.SpellGo{}), do: entity

  def emit(%Character{} = entity, %Effects.StandState{} = effect) do
    Network.send_packet(%Message.SmsgStandstateUpdate{stand_state: effect.stand_state})
    entity
  end

  def emit(entity, %Effects.StandState{}), do: entity

  def emit(%Character{} = entity, %Effects.ChannelStart{} = effect) do
    Network.send_packet(%Message.MsgChannelStart{
      spell_id: effect.spell_id,
      duration_ms: effect.channel_time_ms
    })

    entity
  end

  def emit(entity, %Effects.ChannelStart{}), do: entity

  def emit(%Character{} = entity, %Effects.ChannelUpdate{} = effect) do
    Network.send_packet(%Message.MsgChannelUpdate{time_ms: effect.channel_time_ms})
    entity
  end

  def emit(entity, %Effects.ChannelUpdate{}), do: entity

  def emit(entity, %Effects.DeliverSpell{} = effect) do
    case projectile_delay_ms(entity, effect) do
      delay_ms when is_integer(delay_ms) and delay_ms > 0 ->
        Process.send_after(self(), {:deliver_spell, effect}, delay_ms)

      _ ->
        deliver_spell(effect)
    end

    entity
  end

  def emit(entity, %Effects.DeliverSpellOutcome{} = effect) do
    Entity.receive_spell_outcome(effect.target_guid, effect.source_guid, effect.spell, effect.outcome)
    entity
  end

  def emit(entity, %Effects.RemoveAura{} = effect) do
    Entity.remove_aura(effect.target_guid, effect.spell_id, effect.source_guid)
    entity
  end

  def emit(entity, %Effects.DrainPower{target_guid: target_guid, misc_value: power_type}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.drain_power(target_guid, power_type)
    end

    entity
  end

  def emit(entity, %Effects.GrantPower{} = effect) do
    if Guid.entity_type(effect.target_guid) == :player do
      Entity.grant_power(effect.target_guid, effect.misc_value, effect.amount)
    end

    entity
  end

  def emit(entity, %Effects.DeliverSpellToQuery{spell: %Spell{} = spell} = effect) do
    excluded = MapSet.new(effect.exclude_guids)

    entity
    |> SpellTargetResolver.resolve_query(effect.query)
    |> Enum.reject(&MapSet.member?(excluded, &1))
    |> Enum.each(fn target_guid ->
      context = %CastContext{
        caster_guid: effect.source_guid,
        caster_level: effect.source_level,
        target_guid: target_guid,
        target_hostile?: Spell.requires_hostile_target?(spell),
        spell: spell
      }

      Entity.receive_spell(target_guid, context, spell)
    end)

    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.SpellDelayed{} = effect) do
    Network.send_packet(%Message.SmsgSpellDelayed{caster: guid, delay_ms: effect.delay_ms})
    entity
  end

  def emit(entity, %Effects.SpellDelayed{}), do: entity

  def emit(entity, %Effects.DelayAura{target_guid: target_guid} = effect)
      when is_integer(target_guid) and target_guid > 0 do
    Entity.delay_aura(target_guid, effect.spell_id, effect.source_guid, effect.delay_ms)
    entity
  end

  def emit(entity, %Effects.DelayAura{}), do: entity

  def emit(
        %{object: %{guid: guid}} = entity,
        %Effects.TriggerSpell{source_guid: source, resolve_targets?: true} = effect
      )
      when is_integer(source) and source != guid do
    Entity.trigger_spell(source, effect.spell_id, effect.target_guid,
      base_points: effect.amount,
      effect_index: effect.slot,
      resolve_targets?: true,
      triggered_by_spell_id: effect.triggering_spell_id
    )

    entity
  end

  def emit(entity, %Effects.TriggerSpell{} = effect) do
    case SpellLoader.load(effect.spell_id) do
      nil ->
        entity

      spell ->
        spell = scripted_proc_spell(spell, effect)
        spell = apply_trigger_override(spell, effect)
        dispatch_trigger_effect(entity, effect, spell)
    end
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
       when is_integer(source_guid) and is_atom(proc_type) do
    Entity.spell_outcome(source_guid, %{
      victim_guid: target_guid,
      outcome: if(effect.crit?, do: :crit, else: :normal),
      damage: max((effect.damage || 0) - (absorbed || 0), 0),
      proc_type: proc_type,
      spell_id: effect.spell_id
    })
  end

  defp notify_spell_outcome(_effect, _absorbed), do: :ok

  defp scripted_proc_spell(%Spell{} = spell, %Effects.TriggerSpell{triggering_spell_id: triggering_spell_id}) do
    case Scripts.proc_trigger_spell_id(spell, triggering_spell_id) do
      spell_id when spell_id == spell.id -> spell
      spell_id when is_integer(spell_id) -> SpellLoader.load(spell_id)
      _missing -> nil
    end
  end

  defp dispatch_trigger_effect(entity, effect, %Spell{} = spell) do
    if effect.resolve_targets? or SpellTarget.area_targeted?(spell) do
      dispatch_resolved_trigger(entity, effect, spell)
    else
      dispatch_single_trigger(entity, effect, spell)
    end
  end

  defp dispatch_trigger_effect(entity, _effect, _spell), do: entity

  defp dispatch_single_trigger(entity, effect, spell) do
    case triggered_target(entity, effect, spell) do
      nil ->
        entity

      target_guid ->
        effect = %{effect | target_guid: target_guid}

        entity
        |> emit(
          Effects.spell_go(
            effect.source_guid || entity.object.guid,
            effect.spell_id,
            [target_guid],
            Target.unit(target_guid)
          )
        )
        |> dispatch_triggered_spell(effect, spell)
    end
  end

  defp dispatch_resolved_trigger(entity, effect, spell) do
    targets = SpellTargetResolver.resolve(entity, spell, Target.unit(effect.target_guid))

    entity =
      emit(
        entity,
        Effects.spell_go(
          effect.source_guid || entity.object.guid,
          effect.spell_id,
          targets,
          Target.unit(effect.target_guid)
        )
      )

    Enum.reduce(targets, entity, fn target_guid, current ->
      dispatch_triggered_spell(current, %{effect | target_guid: target_guid}, spell)
    end)
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

  defp projectile_delay_ms(_entity, _effect), do: 0

  defp dispatch_triggered_spell(entity, %Effects.TriggerSpell{} = effect, spell) do
    context = trigger_context(entity, effect, spell)
    Entity.receive_spell(effect.target_guid, context, spell)
    entity
  end

  defp apply_trigger_override(%Spell{} = spell, %Effects.TriggerSpell{} = effect) do
    spell
    |> apply_trigger_effect_override(effect)
    |> apply_trigger_duration_override(effect)
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

  defp apply_trigger_effect_override(spell, _effect), do: spell

  defp apply_trigger_duration_override(%Spell{} = spell, %Effects.TriggerSpell{duration_ms: duration_ms})
       when is_integer(duration_ms) and duration_ms > 0 do
    %{spell | duration_ms: duration_ms, max_duration_ms: duration_ms}
  end

  defp apply_trigger_duration_override(spell, _effect), do: spell

  defp triggered_target(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    SpellTarget.redirect_trigger_target(entity, effect.target_guid, spell)
  end

  defp triggered_target(_entity, %Effects.TriggerSpell{} = effect, _spell), do: effect.target_guid

  defp trigger_context(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    %{
      CastContext.from_caster(entity, spell, effect.target_guid)
      | target_hostile?: Spell.requires_hostile_target?(spell),
        target_role: effect.target_role
    }
  end

  defp trigger_context(_entity, %Effects.TriggerSpell{} = effect, spell) do
    %CastContext{
      caster_guid: effect.source_guid,
      caster_level: effect.source_level || 1,
      target_guid: effect.target_guid,
      target_role: effect.target_role,
      target_hostile?: Spell.requires_hostile_target?(spell),
      spell: spell
    }
  end
end
