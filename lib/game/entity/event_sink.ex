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
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @victimstate_normal 1

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
      periodic?: event.periodic?
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

  def emit(entity, %Event{type: :spell_cast_result, spell_id: spell_id}) do
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

  def emit(%Character{} = entity, %Event{type: :spell_cooldown} = event) do
    Network.send_packet(%Message.SmsgSpellCooldown{
      guid: event.source_guid,
      cooldowns: [{event.spell_id, event.duration_ms}]
    })

    entity
  end

  def emit(entity, %Event{type: :spell_cooldown}), do: entity

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :spell_go} = event) when is_integer(guid) do
    %Message.SmsgSpellGo{
      cast_item: event.cast_item_guid || event.source_guid || guid,
      caster: event.source_guid || guid,
      spell: event.spell_id,
      flags: 0x100,
      hits: event.hit_guids || [],
      misses: [],
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

  def emit(entity, %Event{type: :attack_start} = event) do
    %Message.SmsgAttackstart{
      attacker: event.source_guid,
      victim: event.target_guid
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

  def emit(entity, %Event{type: :attacker_gained, target_guid: target_guid}) do
    Metadata.increment(target_guid, :attacker_count)
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

  def emit(%Character{} = entity, %Event{type: :teleport_to_spell_target, spell_id: spell_id}) do
    case SpellLoader.target_position(spell_id) do
      %{map: map, x: x, y: y, z: z} -> GenServer.cast(self(), {:start_teleport, x, y, z, map})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Event{type: :teleport_to_spell_target}), do: entity

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

  def emit(entity, %Event{type: :trigger_spell} = event) do
    case SpellLoader.load(event.spell_id) do
      nil ->
        entity

      spell ->
        case SpellTarget.redirect_enemy_trigger(entity, event.target_guid, spell) do
          nil -> entity
          target_guid -> dispatch_triggered_spell(entity, %{event | target_guid: target_guid}, spell)
        end
    end
  end

  def emit(entity, _event), do: entity

  def deliver_spell(%Event{type: :deliver_spell} = event) do
    Entity.receive_spell(event.target_guid, event.cast_context, event.spell)
  end

  defp notify_chasers(%{object: %{guid: guid}, movement_block: %{position: {x, y, z, _o}}}) do
    ChaseWatch.notify_moved(guid, {x, y, z})
  end

  defp owner_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp owner_level(_entity), do: 1

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
    context = trigger_context(event, spell)
    {entity, events} = SpellEffect.receive(entity, context, spell, Time.now())
    emit(entity, events)
  end

  defp dispatch_triggered_spell(entity, %Event{} = event, spell) do
    context = trigger_context(event, spell)
    emit(entity, Event.deliver_spell(event.target_guid, context, spell))
  end

  defp trigger_context(%Event{} = event, spell) do
    %CastContext{
      caster_guid: event.source_guid,
      caster_level: event.source_level || 1,
      target_guid: event.target_guid,
      spell: spell
    }
  end
end
