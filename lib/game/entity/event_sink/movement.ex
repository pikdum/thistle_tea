defmodule ThistleTea.Game.Entity.EventSink.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement, as: MovementLogic
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Visibility

  def emit(%Mob{} = entity, %Effects.MovementInform{motion_type: type, point_id: point}, context) do
    Context.cast(context, {:movement_inform, type, point})
    entity
  end

  def emit(entity, %Effects.MovementInform{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.MovementStopped{}, _context) do
    World.update_position(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(
        %Mob{object: %{guid: guid}, internal: %Internal{}} = entity,
        %Effects.CreatureTeleported{
          world: world,
          from_position: {from_x, from_y, from_z, _from_orientation},
          position: {_x, _y, _z, orientation},
          movement_block: %MovementBlock{} = movement_block
        },
        _context
      ) do
    snapshot = %{
      entity
      | movement_block: movement_block,
        internal: %{entity.internal | world: world}
    }

    packet = %Message.MsgMoveTeleport{guid: guid, movement_block: movement_block}
    old_observers = World.tracking_players_at(world, {from_x, from_y, from_z})
    World.broadcast_packet(packet, snapshot, recipients: old_observers)

    World.update_position(snapshot)
    snapshot = Visibility.refresh_entity(snapshot)
    Metadata.update(guid, %{orientation: orientation})
    notify_chasers(snapshot)

    {world, x, y, z} = World.position(snapshot)
    new_observers = World.tracking_players_at(world, {x, y, z})
    World.broadcast_packet(packet, snapshot, recipients: new_observers)

    %{entity | internal: %{entity.internal | visibility_cell: snapshot.internal.visibility_cell}}
  end

  def emit(entity, %Effects.CreatureTeleported{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.MovementStopped{}, _context) do
    entity = World.snapshot_position(entity)
    World.update_position(entity)
    entity |> Message.SmsgMonsterMove.build_stop() |> World.broadcast_packet(entity)
    entity
  end

  def emit(
        %Character{object: %{guid: guid}} = entity,
        %Effects.ClientControlChanged{allow_movement?: allowed?},
        context
      ) do
    Presence.relocate(entity, %{movement_velocity: {0.0, 0.0, 0.0}, moving_until: nil, airborne?: false})

    case entity.internal.possession do
      %{kind: :possession, caster_guid: controller} ->
        Context.send_packet(context, %Message.SmsgClientControlUpdate{guid: guid, allow_movement?: false})

        World.broadcast_packet(%Message.SmsgClientControlUpdate{guid: guid, allow_movement?: allowed?}, entity,
          recipients: [controller]
        )

      %{kind: :charm} ->
        Context.send_packet(context, %Message.SmsgClientControlUpdate{guid: guid, allow_movement?: false})

      nil ->
        Context.send_packet(context, %Message.SmsgClientControlUpdate{guid: guid, allow_movement?: allowed?})
    end

    entity
  end

  def emit(
        %Mob{object: %{guid: guid}, internal: %{pet: %Pet{possessed?: true, owner_guid: owner}}} = entity,
        %Effects.ClientControlChanged{allow_movement?: allowed?},
        _context
      ) do
    World.broadcast_packet(%Message.SmsgClientControlUpdate{guid: guid, allow_movement?: allowed?}, entity,
      recipients: [owner]
    )

    entity
  end

  def emit(entity, %Effects.ClientControlChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: true}, context) do
    send_control_packet(entity, %Message.SmsgForceMoveRoot{guid: guid}, context)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: false}, context) do
    send_control_packet(entity, %Message.SmsgForceMoveUnroot{guid: guid}, context)
    entity
  end

  def emit(entity, %Effects.MovementRootChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: true}, context) do
    send_control_packet(entity, %Message.SmsgMoveFeatherFall{guid: guid}, context)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: false}, context) do
    send_control_packet(entity, %Message.SmsgMoveNormalFall{guid: guid}, context)
    entity
  end

  def emit(entity, %Effects.FeatherFallChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: true}, context) do
    send_control_packet(entity, %Message.SmsgMoveSetHover{guid: guid}, context)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: false}, context) do
    send_control_packet(entity, %Message.SmsgMoveUnsetHover{guid: guid}, context)
    entity
  end

  def emit(entity, %Effects.HoverChanged{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.Knockback{} = effect, context) do
    send_control_packet(entity, knockback_packet(entity, effect), context)
    entity
  end

  def emit(
        %Mob{internal: %{pet: %Pet{possessed?: true, owner_guid: owner}}} = entity,
        %Effects.Knockback{} = effect,
        _context
      ) do
    World.broadcast_packet(knockback_packet(entity, effect), entity, recipients: [owner])
    entity
  end

  def emit(entity, %Effects.Knockback{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: true}, context) do
    send_control_packet(entity, %Message.SmsgMoveWaterWalk{guid: guid}, context)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: false}, context) do
    send_control_packet(entity, %Message.SmsgMoveLandWalk{guid: guid}, context)
    entity
  end

  def emit(entity, %Effects.WaterWalkChanged{}, _context), do: entity

  def emit(
        %Character{object: %{guid: guid}} = entity,
        %Effects.MovementSpeedChanged{speed: speed, movement_type: type},
        context
      )
      when is_number(speed) do
    send_control_packet(entity, speed_packet(type, guid, speed), context)
    broadcast_speed(entity, type, speed)
    entity
  end

  def emit(%Mob{} = entity, %Effects.MovementSpeedChanged{movement_type: type, speed: speed}, context) do
    controlled_speed(entity, type, speed)
    {entity, events} = MovementLogic.retime(entity, type, Time.now())
    Enum.reduce(events, entity, &emit(&2, &1, context))
  end

  def emit(entity, %Effects.MovementSpeedChanged{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.MonsterMove{move_opts: opts}, _context) do
    World.update_position(entity)
    notify_chasers(entity)

    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.MonsterMove{move_opts: opts}, _context) do
    World.update_position(entity)

    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.MonsterMove{}, _context), do: entity

  def emit(%{unit: %Unit{}} = entity, %Effects.ChargeResolved{} = effect, context) do
    command = %Commands.ChargePathResolved{
      path: effect.path,
      duration_ms: effect.duration_ms,
      started_at: Time.now()
    }

    Context.send(context, command)
    entity
  end

  def emit(entity, %Effects.ChargeResolved{}, _context), do: entity

  def emit(%Character{internal: %{world: world}} = entity, %Effects.Teleport{position: {x, y, z, o}}, context) do
    Context.cast(context, {:start_teleport, x, y, z, o, world})
    entity
  end

  def emit(entity, %Effects.Teleport{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.BindHome{binder_guid: guid}, context) do
    Context.cast(context, {:bind_home, guid})
    entity
  end

  def emit(entity, %Effects.BindHome{}, _context), do: entity

  def emit(
        %Character{} = entity,
        %Effects.TeleportToWorld{world: world, position: {x, y, z}, orientation: orientation, preserve_combat?: true},
        context
      ) do
    orientation = orientation || elem(entity.movement_block.position, 3)
    Context.cast(context, {:combat_teleport, x, y, z, orientation, world})
    entity
  end

  def emit(
        %Mob{internal: %Internal{world: world}} = entity,
        %Effects.TeleportToWorld{world: world, position: {x, y, z}, orientation: orientation, preserve_combat?: true},
        context
      ) do
    orientation = orientation || elem(entity.movement_block.position, 3)
    {entity, transition} = MovementLogic.teleport(entity, {x, y, z, orientation}, Time.now())

    entity = %{
      entity
      | internal: %{
          entity.internal
          | blackboard: entity.internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_move_target()
        }
    }

    effect =
      Effects.creature_teleported(
        world,
        transition.from_position,
        transition.position,
        transition.movement_block,
        0,
        world.map_id,
        0
      )

    emit(entity, effect, context)
  end

  def emit(%Character{} = entity, %Effects.TeleportToWorld{world: world, position: {x, y, z}}, context) do
    Context.cast(context, {:start_teleport, x, y, z, world})
    entity
  end

  def emit(entity, %Effects.TeleportToWorld{}, _context), do: entity

  def emit(entity, %Effects.SetFacing{facing: facing}, _context) do
    Message.SmsgMonsterMove.build_face(entity, facing)
    |> World.broadcast_packet(entity)

    entity
  end

  defp send_control_packet(
         %Character{internal: %{possession: %{kind: :possession, caster_guid: controller}}} = entity,
         packet,
         _context
       ) do
    World.broadcast_packet(packet, entity, recipients: [controller])
  end

  defp send_control_packet(_entity, packet, context), do: Context.send_packet(context, packet)

  defp speed_packet(:run_speed, guid, speed), do: %Message.SmsgForceRunSpeedChange{guid: guid, speed: speed}
  defp speed_packet(:run_back_speed, guid, speed), do: %Message.SmsgForceRunBackSpeedChange{guid: guid, speed: speed}
  defp speed_packet(:swim_speed, guid, speed), do: %Message.SmsgForceSwimSpeedChange{guid: guid, speed: speed}
  defp speed_packet(:swim_back_speed, guid, speed), do: %Message.SmsgForceSwimBackSpeedChange{guid: guid, speed: speed}

  defp controlled_speed(%Mob{internal: %{pet: %Pet{possessed?: true, owner_guid: owner}}} = entity, type, speed) do
    World.broadcast_packet(speed_packet(type, entity.object.guid, speed), entity, recipients: [owner])
    broadcast_speed(entity, type, speed)
  end

  defp controlled_speed(_entity, _type, _speed), do: :ok

  defp broadcast_speed(%{object: %{guid: guid}, movement_block: %MovementBlock{} = movement} = entity, type, speed) do
    packet = struct!(observer_speed_module(type), guid: guid, movement_block: movement, speed: speed)
    World.broadcast_packet(packet, entity, include_self?: false)
  end

  defp broadcast_speed(_entity, _type, _speed), do: :ok

  defp observer_speed_module(:run_speed), do: Message.MsgMoveSetRunSpeed
  defp observer_speed_module(:run_back_speed), do: Message.MsgMoveSetRunBackSpeed
  defp observer_speed_module(:swim_speed), do: Message.MsgMoveSetSwimSpeed
  defp observer_speed_module(:swim_back_speed), do: Message.MsgMoveSetSwimBackSpeed

  defp notify_chasers(%{object: %{guid: guid}, movement_block: %{position: {x, y, z, _o}}}) do
    ChaseWatch.notify_moved(guid, {x, y, z})
  end

  defp knockback_packet(entity, effect) do
    %Message.SmsgMoveKnockBack{
      guid: entity.object.guid,
      cos_angle: effect.cos_angle,
      sin_angle: effect.sin_angle,
      horizontal_speed: effect.horizontal_speed,
      vertical_speed: -effect.vertical_speed
    }
  end
end
