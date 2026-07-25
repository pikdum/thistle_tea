defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Boundary that drains the events queued on an entity by pure logic and
  performs their side effects: building packets, broadcasting to nearby
  players, and messaging other entity processes.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate, as: DataGameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Combat, as: CombatEffects
  alias ThistleTea.Game.Entity.EventSink.Movement, as: MovementEffects
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
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
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

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

  def emit(
        %{object: %{guid: caster_guid}, internal: %Internal{world: world}} = entity,
        %Effects.SpawnAreaEffect{} = event
      ) do
    radius =
      case event.effect do
        %{radius_yards: radius} when is_number(radius) and radius > 0 -> radius
        _ -> 8.0
      end

    dynamic_object = DataDynamicObject.build(caster_guid, world, event.spell, event.position, radius)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: event.duration_ms,
      tick: DynamicObjectServer.tick_config(entity, event.spell, event.effect)
    })

    entity
  end

  def emit(entity, %Effects.SpawnAreaEffect{}), do: entity

  def emit(
        %Character{object: %{guid: caster_guid}, player: player, internal: %Internal{world: world}} = entity,
        %Effects.SpawnFarsight{spell: %Spell{} = spell, position: position, duration_ms: duration_ms}
      ) do
    dynamic_object = DataDynamicObject.build(caster_guid, world, spell, position, 0.0)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: duration_ms,
      farsight_owner_guid: caster_guid
    })

    Entity.request_update_from(dynamic_object.object.guid, caster_guid)
    send(self(), {:viewpoint_granted, dynamic_object.object.guid})

    %{entity | player: %{player | farsight: dynamic_object.object.guid}}
    |> Core.mark_broadcast_update()
  end

  def emit(entity, %Effects.SpawnFarsight{}), do: entity

  def emit(%{object: %{guid: caster_guid}} = entity, %Effects.DespawnAreaEffects{spell_id: spell_id})
      when is_integer(caster_guid) do
    caster_guid
    |> AreaEffects.pids(spell_id)
    |> Enum.each(&World.stop_entity/1)

    entity
  end

  def emit(entity, %Effects.DespawnAreaEffects{}), do: entity

  def emit(entity, %Effects.DespawnEntity{target_guid: guid}) when is_integer(guid) do
    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.DespawnEntity{}), do: entity

  def emit(entity, %Effects.LeaveRitual{target_guid: game_object_guid, source_guid: user_guid}) do
    Entity.leave_ritual(game_object_guid, user_guid)
    entity
  end

  def emit(
        %{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: {_x, _y, _z, _o} = position}
        } = entity,
        %Effects.SummonGameObject{entry: entry, duration_ms: duration_ms} = event
      ) do
    case GameObjectTemplateLoader.get(entry) do
      %DataGameObjectTemplate{} = template ->
        game_object =
          GameObject.build_summoned(template, world, position,
            summoned_by: owner_guid,
            level: owner_level(entity),
            despawn_in_ms: duration_ms,
            ritual_target_guid: event.target_guid,
            ritual_zone_id: zone_id(world, position)
          )

        World.start_entity(game_object)

        track_channel_game_object(entity, game_object)

      _ ->
        entity
    end
  end

  def emit(entity, %Effects.SummonGameObject{}), do: entity

  def emit(entity, %Effects.SummonRequest{
        source_guid: summoner_guid,
        target_guid: target_guid,
        amount: zone_id,
        position: {world, x, y, z}
      }) do
    Entity.request_summon(target_guid, summoner_guid, zone_id, world, {x, y, z})
    entity
  end

  def emit(entity, %Effects.SummonRequest{}), do: entity

  def emit(%{internal: %Internal{world: world}} = entity, %Effects.SummonCreature{summon: summon} = event) do
    with true <- summon_allowed?(world, summon),
         %Mob{} = mob <-
           SummonLoader.build(summon.entry, world, summon.position,
             despawn_type: summon.despawn_type,
             despawn_delay_ms: summon.despawn_delay_ms,
             run?: summon.run?
           ),
         mob = put_summon_owner(mob, summon),
         mob = maybe_possess_summon(mob, entity, summon),
         {:ok, pid} <- MobLoader.start_mob(mob) do
      if is_integer(event.target_guid) and event.target_guid > 0 and summon.attack_target != nil do
        send(pid, {:force_attack, event.target_guid})
      end

      if event.steps != [] do
        send(pid, {:ai_script_steps, event.steps, event.target_guid})
      end

      cast_post_spawn_spells(entity, mob.object.guid, summon)
      notify_possession_granted(entity, mob, summon)
    end

    entity
  end

  def emit(entity, %Effects.SummonCreature{}), do: entity

  def emit(entity, %Effects.ControlGranted{} = event) do
    case Entity.pid(event.source_guid) do
      pid when is_pid(pid) ->
        send(pid, {:control_granted, event.target_guid, event.spell_id, event.spells, event.enabled?})

      _ ->
        nil
    end

    entity
  end

  def emit(entity, %Effects.ControlReleased{} = event) do
    case Entity.pid(event.source_guid) do
      pid when is_pid(pid) -> send(pid, {:control_released, event.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ReleaseControlled{} = event) do
    case Entity.pid(event.target_guid) do
      pid when is_pid(pid) -> send(pid, {:release_control, event.source_guid, event.spell_id})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointGranted{} = event) do
    case Entity.pid(event.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_granted, event.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.ViewpointReleased{} = event) do
    case Entity.pid(event.source_guid) do
      pid when is_pid(pid) -> send(pid, {:viewpoint_released, event.target_guid})
      _ -> nil
    end

    entity
  end

  def emit(%Character{} = entity, %Effects.SummonPet{entry: entry, spell_id: spell_id}) do
    with %Mob{} = built_pet <- SummonLoader.build_pet(entry, entity),
         pet = %{built_pet | unit: %{built_pet.unit | created_by_spell: spell_id}},
         {:ok, pid} <- MobLoader.start_mob(pet) do
      old_pet_guid = entity.unit.summon

      if is_integer(old_pet_guid) and old_pet_guid > 0 and old_pet_guid != pet.object.guid do
        World.stop_entity(old_pet_guid)
      end

      send(pid, {:attach_pet, self(), spell_id, Map.values(pet.internal.spellbook)})
    end

    entity
  end

  def emit(entity, %Effects.SummonPet{}), do: entity

  def emit(%Mob{object: %{guid: guid}} = entity, %Effects.TameCreature{source_guid: owner_guid, entry: entry}) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:tame_pet, entry})
      _ -> nil
    end

    World.stop_entity(guid)
    entity
  end

  def emit(entity, %Effects.TameCreature{}), do: entity

  def emit(%Character{unit: %Unit{summon: pet_guid}} = entity, %Effects.DismissPet{} = event)
      when is_integer(pet_guid) and pet_guid > 0 do
    World.stop_entity(pet_guid)
    Network.send_packet(Message.SmsgPetSpells.clear())

    internal =
      if event.reason == :owner_died do
        entity.internal
      else
        %{entity.internal | active_pet_entry: nil, active_pet_spell_id: nil}
      end

    %{entity | unit: %{entity.unit | summon: 0}, internal: internal}
  end

  def emit(entity, %Effects.DismissPet{}), do: entity

  def emit(
        %Character{
          object: %{guid: owner_guid},
          internal: %Internal{world: world},
          movement_block: %{position: position}
        } = entity,
        %Effects.SummonTotem{entry: entry, slot: slot, duration_ms: duration_ms}
      ) do
    old_guid = Map.get(entity.internal.totem_guids, slot)
    if is_integer(old_guid), do: World.stop_entity(old_guid)

    with %Mob{} = built <-
           SummonLoader.build(entry, world, position, despawn_type: 1, despawn_delay_ms: duration_ms),
         built = SummonLoader.attach_owner(built, owner_guid),
         unit = %{
           built.unit
           | faction_template: entity.unit.faction_template,
             level: entity.unit.level
         },
         totem = %{
           built
           | unit: unit,
             internal: %{
               built.internal
               | rooted?: true,
                 totem: %Totem{owner_guid: owner_guid}
             }
         },
         {:ok, _pid} <- MobLoader.start_mob(totem) do
      totem_guids = Map.put(entity.internal.totem_guids, slot, totem.object.guid)
      %{entity | internal: %{entity.internal | totem_guids: totem_guids}}
    else
      _ -> entity
    end
  end

  def emit(entity, %Effects.SummonTotem{}), do: entity

  def emit(entity, %Effects.DespawnSelf{} = event) do
    Process.send_after(self(), {:despawn_creature, event.respawn_delay_ms}, event.duration_ms || 0)
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

  defp track_channel_game_object(%{internal: %Internal{} = internal, unit: %Unit{} = unit} = entity, %GameObject{
         object: %{guid: guid},
         internal: %Internal{ritual: %Ritual{}}
       }) do
    %{
      entity
      | internal: %{internal | channel_game_object_guid: guid, channel_game_object_owned?: true},
        unit: %{unit | channel_object: guid}
    }
    |> Core.mark_broadcast_update()
  end

  defp track_channel_game_object(entity, %GameObject{}), do: entity

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

  defp owner_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp owner_level(_entity), do: 1

  defp zone_id(%{map_id: map_id}, {x, y, z, _orientation}) do
    case Pathfinding.get_zone_and_area(map_id, {x, y, z}) do
      {zone_id, _area_id} -> zone_id
      _missing -> 0
    end
  end

  @summon_unique_default_range 50.0
  @corpse_counting_despawn_types [3, 4, 8]

  defp summon_allowed?(map, %{unique?: true, entry: entry, position: {x, y, z, _o}} = summon) do
    limit = max(summon.unique_limit, 1)
    range = if summon.unique_distance > 0, do: summon.unique_distance, else: @summon_unique_default_range
    count_dead? = summon.despawn_type in @corpse_counting_despawn_types

    existing =
      map
      |> World.nearby_mobs_at({x, y, z}, range)
      |> Enum.count(fn {guid, _distance} ->
        Guid.entry(guid) == entry and (count_dead? or summon_alive?(guid))
      end)

    existing < limit
  end

  defp summon_allowed?(_map, _summon), do: true

  defp summon_alive?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> false
      _ -> true
    end
  end

  defp put_summon_owner(%Mob{} = mob, %{owner_guid: owner_guid}) when is_integer(owner_guid) do
    SummonLoader.attach_owner(mob, owner_guid)
  end

  defp put_summon_owner(%Mob{} = mob, _summon), do: mob

  defp maybe_possess_summon(%Mob{} = mob, entity, %{control: :possessed, control_spell_id: spell_id}) do
    SummonLoader.possess(mob, entity, spell_id)
  end

  defp maybe_possess_summon(%Mob{} = mob, _entity, _summon), do: mob

  defp notify_possession_granted(entity, %Mob{object: %{guid: guid}, internal: %Internal{spellbook: spellbook}}, %{
         control: :possessed,
         control_spell_id: spell_id
       }) do
    spells = (spellbook || %{}) |> Map.values() |> Enum.reject(&Spell.attribute?(&1, :passive))

    emit(entity, Effects.control_granted(entity.object.guid, guid, spell_id, spells, possess?: true))

    :ok
  end

  defp notify_possession_granted(_entity, _mob, _summon), do: :ok

  defp cast_post_spawn_spells(entity, summon_guid, %{post_spawn_spells: spells}) when is_list(spells) do
    Enum.each(spells, fn
      %{caster: :owner, spell_id: spell_id} ->
        with %Spell{} = spell <- SpellLoader.load(spell_id) do
          Entity.receive_spell(summon_guid, CastContext.from_caster(entity, spell, summon_guid), spell)
        end

      %{caster: :summon, spell_id: spell_id, resolve_targets?: resolve_targets?} ->
        Entity.trigger_spell(summon_guid, spell_id, summon_guid, resolve_targets?: resolve_targets?)

      _ ->
        nil
    end)
  end

  defp cast_post_spawn_spells(_entity, _summon_guid, _summon), do: :ok

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
