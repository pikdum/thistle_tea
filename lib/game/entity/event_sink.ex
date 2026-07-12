defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Boundary that drains the events queued on an entity by pure logic and
  performs their side effects: building packets, broadcasting to nearby
  players, and messaging other entity processes.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate, as: DataGameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon, as: SummonLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @victimstate_normal 1
  @heal_threat_radius 100.0
  @spell_hit_type_crit 0x2

  def emit_pending(entity) do
    {entity, events} = Event.drain(entity)
    emit(entity, events)
  end

  def emit(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &emit(&2, &1))
  end

  def emit(entity, %Event{type: :spell_damage} = event) do
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

    entity
  end

  def emit(entity, %Event{type: :spell_log_miss} = event) do
    %Message.SmsgSpellLogMiss{
      spell_id: event.spell_id,
      caster: event.source_guid,
      targets: [{event.target_guid, event.reason}]
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :periodic_aura_log} = event) do
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

  def emit(entity, %Event{type: :aura_duration} = event) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: event.aura_slot,
      duration_ms: event.duration_ms
    })

    entity
  end

  def emit(%Mob{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)
    World.clear_movement(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_root_changed, rooted?: true}) do
    Network.send_packet(%Message.SmsgForceMoveRoot{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_root_changed, rooted?: false}) do
    Network.send_packet(%Message.SmsgForceMoveUnroot{guid: guid})
    entity
  end

  def emit(entity, %Event{type: :movement_root_changed}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :feather_fall_changed, enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveFeatherFall{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :feather_fall_changed, enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveNormalFall{guid: guid})
    entity
  end

  def emit(entity, %Event{type: :feather_fall_changed}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :hover_changed, enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveSetHover{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :hover_changed, enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveUnsetHover{guid: guid})
    entity
  end

  def emit(entity, %Event{type: :hover_changed}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :water_walk_changed, enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveWaterWalk{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :water_walk_changed, enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveLandWalk{guid: guid})
    entity
  end

  def emit(entity, %Event{type: :water_walk_changed}), do: entity

  def emit(%Character{} = entity, %Event{type: :resurrect_request} = event) do
    Network.send_packet(%Message.SmsgResurrectRequest{guid: event.source_guid})
    entity
  end

  def emit(entity, %Event{type: :resurrect_request}), do: entity

  def emit(entity, %Event{type: :heal_entity} = event) do
    Entity.receive_heal(event.target_guid, event.amount)
    entity
  end

  def emit(entity, %Event{type: :heal_threat} = event) do
    entity
    |> World.nearby_mobs(@heal_threat_radius)
    |> Enum.each(fn {guid, _distance} ->
      Entity.heal_threat(guid, event.source_guid, event.target_guid, event.amount)
    end)

    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_speed_changed, speed: speed})
      when is_number(speed) do
    Network.send_packet(%Message.SmsgForceRunSpeedChange{guid: guid, speed: speed})
    entity
  end

  def emit(entity, %Event{type: :movement_speed_changed}), do: entity

  def emit(%Mob{} = entity, %Event{type: :monster_move, move_opts: opts}) do
    World.publish_movement(entity)
    notify_chasers(entity)

    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :monster_move}), do: entity

  def emit(%Character{} = entity, %Event{type: :spell_cast_result, spell_id: spell_id}) do
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

  def emit(entity, %Event{type: :spell_cast_result}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :spell_cast_failed} = event) do
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

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :spell_cast_failed} = event) do
    %Message.SmsgSpellFailedOther{caster: guid, id: event.spell_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :spell_start} = event) when is_integer(guid) do
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

  def emit(entity, %Event{type: :spell_start}), do: entity

  def emit(%Character{} = entity, %Event{type: :spell_cooldown} = event) do
    Network.send_packet(%Message.SmsgSpellCooldown{
      guid: event.source_guid,
      cooldowns: [{event.spell_id, event.duration_ms}]
    })

    entity
  end

  def emit(entity, %Event{type: :spell_cooldown}), do: entity

  def emit(%Character{} = entity, %Event{type: :cooldown_event} = event) do
    Network.send_packet(%Message.SmsgCooldownEvent{spell_id: event.spell_id, guid: event.source_guid})
    entity
  end

  def emit(entity, %Event{type: :cooldown_event}), do: entity

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :spell_go} = event) when is_integer(guid) do
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

  def emit(entity, %Event{type: :spell_go}), do: entity

  def emit(%Character{} = entity, %Event{type: :stand_state} = event) do
    Network.send_packet(%Message.SmsgStandstateUpdate{stand_state: event.stand_state})
    entity
  end

  def emit(entity, %Event{type: :stand_state}), do: entity

  def emit(%Character{} = entity, %Event{type: :channel_start} = event) do
    Network.send_packet(%Message.MsgChannelStart{
      spell_id: event.spell_id,
      duration_ms: event.channel_time_ms
    })

    entity
  end

  def emit(entity, %Event{type: :channel_start}), do: entity

  def emit(%Character{} = entity, %Event{type: :channel_update} = event) do
    Network.send_packet(%Message.MsgChannelUpdate{time_ms: event.channel_time_ms})
    entity
  end

  def emit(entity, %Event{type: :channel_update}), do: entity

  def emit(%{internal: %Internal{broadcast_update?: true} = internal} = entity, %Event{type: :object_update} = event) do
    Core.update_object(entity, event.update_type || :values)
    |> World.broadcast_packet(entity)

    %{entity | internal: %{internal | broadcast_update?: false}}
  end

  def emit(entity, %Event{type: :object_update}), do: entity

  def emit(entity, %Event{type: :deliver_attack} = event) do
    Entity.receive_attack(event.target_guid, event.attack)
    entity
  end

  def emit(entity, %Event{type: :deliver_spell} = event) do
    case projectile_delay_ms(entity, event) do
      delay_ms when is_integer(delay_ms) and delay_ms > 0 ->
        Process.send_after(self(), {:deliver_spell, event}, delay_ms)

      _ ->
        deliver_spell(event)
    end

    entity
  end

  def emit(entity, %Event{type: :attack_start, source_guid: source_guid, target_guid: target_guid})
      when is_integer(source_guid) and is_integer(target_guid) do
    %Message.SmsgAttackstart{
      attacker: source_guid,
      victim: target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :attack_stop} = event) do
    %Message.SmsgAttackstop{
      player: event.source_guid,
      enemy: event.target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :attacker_state_update} = event) do
    attack = event.attack || %{}
    damage = event.damage || 0

    %Message.SmsgAttackerstateupdate{
      attacker: event.source_guid,
      target: event.target_guid,
      hit_info: Map.get(attack, :hit_info, 0x2),
      total_damage: damage,
      damages: [
        %{
          spell_school_mask: Map.get(attack, :spell_school_mask, 0),
          damage_float: damage * 1.0,
          damage_uint: damage,
          absorb: Map.get(attack, :absorb, 0),
          resist: Map.get(attack, :resist, 0)
        }
      ],
      damage_state: Map.get(attack, :damage_state, @victimstate_normal),
      unknown1: Map.get(attack, :unknown1, 0),
      spell_id: Map.get(attack, :spell_id, 0),
      blocked_amount: Map.get(attack, :blocked_amount, 0)
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :attack_not_in_range}) do
    Packet.build(<<>>, Opcodes.get(:SMSG_ATTACKSWING_NOTINRANGE))
    |> Network.send_packet()

    entity
  end

  def emit(entity, %Event{type: :drain_rage, target_guid: target_guid}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.drain_rage(target_guid)
    end

    entity
  end

  def emit(entity, %Event{type: :grant_power} = event) do
    if Guid.entity_type(event.target_guid) == :player do
      Entity.grant_power(event.target_guid, event.misc_value, event.amount)
    end

    entity
  end

  @charge_speed 25.0

  def emit(%Character{internal: %Internal{map: map}, movement_block: %{position: {x, y, z, _o}}} = entity, %Event{
        type: :charge,
        target_guid: target_guid
      }) do
    with {^map, tx, ty, tz} <- World.position(target_guid),
         path when is_list(path) and path != [] <- charge_path(map, {x, y, z}, {tx, ty, tz}) do
      duration =
        [{x, y, z} | path]
        |> Math.movement_duration(@charge_speed)
        |> Kernel.*(1_000)
        |> trunc()
        |> max(1)

      movement_block = %{
        entity.movement_block
        | spline_nodes: path,
          duration: duration,
          spline_flags: 0x100
      }

      %{entity | movement_block: movement_block}
      |> Message.SmsgMonsterMove.build()
      |> World.broadcast_packet(entity)

      {dx, dy, dz} = List.last(path)
      destination = {dx, dy, dz, charge_facing({x, y}, {dx, dy})}
      entity = %{entity | movement_block: %{entity.movement_block | position: destination}}
      World.update_position(entity)

      entity
    else
      _no_path -> entity
    end
  end

  def emit(entity, %Event{type: :charge}), do: entity

  def emit(entity, %Event{type: :attack_outcome} = event) do
    Entity.attack_outcome(event.target_guid, %{
      victim_guid: event.source_guid,
      outcome: event.outcome,
      damage: event.damage,
      spell_id: event.spell_id
    })

    entity
  end

  def emit(entity, %Event{type: :attacker_gained, target_guid: target_guid}) do
    Metadata.increment(target_guid, :attacker_count)
    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Event{type: :threat_ref_gained, target_guid: target_guid}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_gained(target_guid, mob_guid)
    end

    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Event{type: :threat_ref_lost, target_guid: target_guid}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_lost(target_guid, mob_guid)
    end

    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :drop_threat, target_guid: mob_guid}) do
    Entity.drop_threat(mob_guid, guid)
    entity
  end

  def emit(entity, %Event{type: :drop_threat}), do: entity

  def emit(%Character{} = entity, %Event{type: :drop_nearby_threat}) do
    Metadata.update(entity.object.guid, StealthDetection.target_metadata(entity))

    entity
    |> World.nearby_mobs(250)
    |> Enum.each(fn {mob_guid, _distance} -> Entity.drop_threat(mob_guid, entity.object.guid) end)

    entity
  end

  def emit(entity, %Event{type: :drop_nearby_threat}), do: entity

  def emit(%Character{} = entity, %Event{type: :blade_flurry, target_guid: primary, damage: damage}) do
    secondary =
      entity
      |> SpellTargetResolver.resolve_query({:caster_aoe, 8.0})
      |> Enum.find(&(&1 != primary))

    if is_integer(secondary) do
      spell = %Spell{
        id: 22_482,
        name: "Blade Flurry",
        school: :physical,
        dmg_class: 2,
        effects: [%Spell.Effect{index: 0, type: :school_damage, base_points: damage}]
      }

      context = CastContext.from_caster(entity, spell, secondary)
      Entity.receive_spell(secondary, context, spell)
    end

    entity
  end

  def emit(entity, %Event{type: :blade_flurry}), do: entity

  def emit(%Character{} = entity, %Event{type: :refresh_party_aura, spell: %Spell{} = spell, amount: radius})
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

  def emit(entity, %Event{type: :refresh_party_aura}), do: entity

  def emit(entity, %Event{type: :redirect_damage} = event) do
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

  def emit(entity, %Event{type: :attacker_lost, target_guid: target_guid}) do
    Metadata.decrement(target_guid, :attacker_count, 0)
    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :tap_cleared}) do
    Metadata.update(guid, %{tapped_player: nil, tapped_group_id: nil})
    entity
  end

  def emit(%Character{internal: %Internal{map: map}} = entity, %Event{type: :teleport, position: {x, y, z, _o}}) do
    GenServer.cast(self(), {:start_teleport, x, y, z, map})
    entity
  end

  def emit(entity, %Event{type: :teleport}), do: entity

  def emit(%Character{internal: %Internal{map: map}} = entity, %Event{type: :leap, position: {x, y, z, _o}}) do
    case clamp_leap_destination(entity, map, {x, y, z}) do
      {nx, ny, nz} -> GenServer.cast(self(), {:start_teleport, nx, ny, nz, map})
      nil -> nil
    end

    entity
  end

  def emit(entity, %Event{type: :leap}), do: entity

  def emit(%Character{internal: %Internal{home_bind: {map, x, y, z}}} = entity, %Event{
        type: :teleport_to_spell_target,
        spell_id: 8690
      }) do
    GenServer.cast(self(), {:start_teleport, x, y, z, map})
    entity
  end

  def emit(%Character{} = entity, %Event{type: :teleport_to_spell_target, spell_id: spell_id}) do
    case SpellLoader.target_position(spell_id) do
      %{map: map, x: x, y: y, z: z} -> GenServer.cast(self(), {:start_teleport, x, y, z, map})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Event{type: :teleport_to_spell_target}), do: entity

  def emit(%Character{} = entity, %Event{type: :consume_cast_item, cast_item_guid: item_guid})
      when is_integer(item_guid) do
    send(self(), {:consume_cast_item, item_guid})
    entity
  end

  def emit(entity, %Event{type: :consume_cast_item}), do: entity

  def emit(%Character{} = entity, %Event{type: :enchant_item} = event) do
    duration_ms = ItemEnchantmentLoader.duration_ms(event.spell.id, event.effect)
    send(self(), {:enchant_item, event.target_guid, event.spell, event.effect.misc_value, duration_ms})
    entity
  end

  def emit(entity, %Event{type: :enchant_item}), do: entity

  def emit(%Character{} = entity, %Event{type: :open_gameobject, target_guid: object_guid})
      when is_integer(object_guid) do
    send(self(), {:open_gameobject_loot, object_guid})
    entity
  end

  def emit(entity, %Event{type: :open_gameobject}), do: entity

  def emit(%Character{} = entity, %Event{type: :create_item, item_id: item_id, count: count}) do
    send(self(), {:create_item, item_id, count})
    entity
  end

  def emit(entity, %Event{type: :create_item}), do: entity

  def emit(%Character{} = entity, %Event{type: :consume_reagents, reagents: reagents}) when is_list(reagents) do
    send(self(), {:consume_reagents, reagents})
    entity
  end

  def emit(entity, %Event{type: :consume_reagents}), do: entity

  def emit(
        %{object: %{guid: caster_guid}, internal: %Internal{map: map}} = entity,
        %Event{type: :spawn_area_effect} = event
      )
      when is_integer(map) do
    radius =
      case event.effect do
        %{radius_yards: radius} when is_number(radius) and radius > 0 -> radius
        _ -> 8.0
      end

    dynamic_object = DataDynamicObject.build(caster_guid, map, event.spell, event.position, radius)

    World.start_entity(%{
      entity: dynamic_object,
      duration_ms: event.duration_ms,
      tick: DynamicObjectServer.tick_config(entity, event.spell, event.effect)
    })

    entity
  end

  def emit(entity, %Event{type: :spawn_area_effect}), do: entity

  def emit(%{object: %{guid: caster_guid}} = entity, %Event{type: :despawn_area_effects, spell_id: spell_id})
      when is_integer(caster_guid) do
    caster_guid
    |> AreaEffects.pids(spell_id)
    |> Enum.each(&World.stop_entity/1)

    entity
  end

  def emit(entity, %Event{type: :despawn_area_effects}), do: entity

  def emit(
        %{
          object: %{guid: owner_guid},
          internal: %Internal{map: map},
          movement_block: %{position: {_x, _y, _z, _o} = position}
        } = entity,
        %Event{type: :summon_game_object, entry: entry, duration_ms: duration_ms}
      )
      when is_integer(map) do
    case GameObjectTemplateLoader.get(entry) do
      %DataGameObjectTemplate{} = template ->
        template
        |> GameObject.build_summoned(map, position,
          summoned_by: owner_guid,
          level: owner_level(entity),
          despawn_in_ms: duration_ms
        )
        |> World.start_entity()

      _ ->
        nil
    end

    entity
  end

  def emit(entity, %Event{type: :summon_game_object}), do: entity

  def emit(%{object: %{guid: guid}, internal: %Internal{name: name}} = entity, %Event{type: :monster_talk} = event) do
    event.chat_type
    |> monster_chat_type()
    |> Message.SmsgMessagechat.monster(event.text, guid, name, event.target_guid)
    |> World.broadcast_packet(entity, range: listen_range(event.chat_type))

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :emote, emote_id: emote_id}) do
    %Message.SmsgEmote{emote: emote_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :script_steps} = event) do
    Process.send_after(self(), {:ai_script_steps, event.steps, event.target_guid}, event.duration_ms || 0)
    entity
  end

  def emit(entity, %Event{type: :forward_script_steps} = event) do
    case Entity.pid(event.target_guid) do
      pid when is_pid(pid) -> send(pid, {:ai_script_steps, event.steps, event.source_guid})
      _ -> nil
    end

    entity
  end

  def emit(%{internal: %Internal{map: map}} = entity, %Event{type: :summon_creature, summon: summon} = event)
      when is_integer(map) do
    with true <- summon_allowed?(map, summon),
         %Mob{} = mob <-
           SummonLoader.build(summon.entry, map, summon.position,
             despawn_type: summon.despawn_type,
             despawn_delay_ms: summon.despawn_delay_ms,
             run?: summon.run?
           ),
         {:ok, pid} <- MobLoader.start_mob(mob) do
      if is_integer(event.target_guid) and event.target_guid > 0 and summon.attack_target != nil do
        send(pid, {:force_attack, event.target_guid})
      end

      if event.steps != [] do
        send(pid, {:ai_script_steps, event.steps, event.target_guid})
      end
    end

    entity
  end

  def emit(entity, %Event{type: :summon_creature}), do: entity

  def emit(entity, %Event{type: :despawn_self} = event) do
    Process.send_after(self(), {:despawn_creature, event.respawn_delay_ms}, event.duration_ms || 0)
    entity
  end

  def emit(entity, %Event{type: :attack_start, target_guid: target_guid})
      when is_integer(target_guid) and target_guid > 0 do
    send(self(), {:force_attack, target_guid})
    entity
  end

  def emit(entity, %Event{type: :attack_start}), do: entity

  def emit(entity, %Event{type: :play_sound, sound_id: sound_id}) do
    %Message.SmsgPlaySound{sound_id: sound_id}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :play_object_sound, sound_id: sound_id}) do
    %Message.SmsgPlayObjectSound{sound_id: sound_id, guid: guid}
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :set_facing, facing: facing}) do
    Message.SmsgMonsterMove.build_face(entity, facing)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :trigger_spell} = event) do
    case SpellLoader.load(event.spell_id) do
      nil ->
        entity

      spell ->
        case triggered_target(entity, event, spell) do
          nil ->
            entity

          target_guid ->
            event = %{event | target_guid: target_guid}

            entity
            |> emit(
              Event.spell_go(
                event.source_guid || entity.object.guid,
                event.spell_id,
                [target_guid],
                Targets.unit(target_guid).raw
              )
            )
            |> dispatch_triggered_spell(event, spell)
        end
    end
  end

  def emit(entity, _event), do: entity

  def deliver_spell(%Event{type: :deliver_spell} = event) do
    Entity.receive_spell(event.target_guid, event.cast_context, event.spell)
  end

  defp monster_chat_type(chat_type) when chat_type in [:yell, :zone_yell], do: :monster_yell
  defp monster_chat_type(chat_type) when chat_type in [:text_emote, :boss_emote, :zone_emote], do: :monster_emote
  defp monster_chat_type(_chat_type), do: :monster_say

  @listen_range_say 25.0
  @listen_range_yell 300.0

  defp listen_range(chat_type) when chat_type in [:yell, :zone_yell], do: @listen_range_yell
  defp listen_range(_chat_type), do: @listen_range_say

  defp notify_chasers(%{object: %{guid: guid}, movement_block: %{position: {x, y, z, _o}}}) do
    ChaseWatch.notify_moved(guid, {x, y, z})
  end

  defp owner_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp owner_level(_entity), do: 1

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

  defp charge_path(map, from, to) do
    Pathfinding.find_path(map, from, to)
  rescue
    _ -> nil
  end

  defp charge_facing({x, y}, {dx, dy}) when dx != x or dy != y do
    :math.atan2(dy - y, dx - x)
  end

  defp charge_facing(_from, _to), do: 0.0

  defp clamp_leap_destination(%{movement_block: %{position: {cx, cy, cz, _o}}}, map, {x, y, z}) do
    z = snap_to_terrain_height(map, {x, y}, z, cz)
    requested = :math.sqrt(:math.pow(x - cx, 2) + :math.pow(y - cy, 2))

    with path when is_list(path) and path != [] <- Pathfinding.find_path(map, {cx, cy, cz}, {x, y, z}),
         total when total > 0 <- Math.movement_duration([{cx, cy, cz} | path], 1.0) do
      walked = min(requested, total)
      Movement.position_at({cx, cy, cz}, path, round(total * 1_000), round(walked * 1_000))
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp clamp_leap_destination(_entity, _map, _position), do: nil

  defp snap_to_terrain_height(map, {x, y}, fallback_z, reference_z) do
    case Pathfinding.find_heights(map, {x, y}) do
      [] -> fallback_z
      heights -> Enum.min_by(heights, &abs(&1 - reference_z))
    end
  end

  defp projectile_delay_ms(%{movement_block: %{position: {x, y, z, _o}}}, %Event{
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

  defp dispatch_triggered_spell(%{object: %{guid: guid}} = entity, %Event{target_guid: guid} = event, spell) do
    context = trigger_context(entity, event, spell)
    {entity, events} = SpellEffect.receive(entity, context, spell, Time.now())
    emit(entity, events)
  end

  defp dispatch_triggered_spell(entity, %Event{} = event, spell) do
    context = trigger_context(entity, event, spell)
    emit(entity, Event.deliver_spell(event.target_guid, context, spell))
  end

  defp triggered_target(%{object: %{guid: guid}} = entity, %Event{source_guid: guid} = event, spell) do
    SpellTarget.redirect_enemy_trigger(entity, event.target_guid, spell)
  end

  defp triggered_target(_entity, %Event{} = event, _spell), do: event.target_guid

  defp trigger_context(%{object: %{guid: guid}} = entity, %Event{source_guid: guid} = event, spell) do
    %{
      CastContext.from_caster(entity, spell, event.target_guid)
      | target_hostile?: Spell.requires_hostile_target?(spell)
    }
  end

  defp trigger_context(_entity, %Event{} = event, spell) do
    %CastContext{
      caster_guid: event.source_guid,
      caster_level: event.source_level || 1,
      target_guid: event.target_guid,
      target_hostile?: Spell.requires_hostile_target?(spell),
      spell: spell
    }
  end
end
