defmodule ThistleTea.Game.Entity.EventSink.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch

  def emit(%Mob{} = entity, %Effects.MovementStopped{}, _context) do
    World.update_position(entity)
    World.clear_movement(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.MovementStopped{}, _context) do
    World.update_position(entity)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: true}, context) do
    Context.send_packet(context, %Message.SmsgForceMoveRoot{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: false}, context) do
    Context.send_packet(context, %Message.SmsgForceMoveUnroot{guid: guid})
    entity
  end

  def emit(entity, %Effects.MovementRootChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: true}, context) do
    Context.send_packet(context, %Message.SmsgMoveFeatherFall{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: false}, context) do
    Context.send_packet(context, %Message.SmsgMoveNormalFall{guid: guid})
    entity
  end

  def emit(entity, %Effects.FeatherFallChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: true}, context) do
    Context.send_packet(context, %Message.SmsgMoveSetHover{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: false}, context) do
    Context.send_packet(context, %Message.SmsgMoveUnsetHover{guid: guid})
    entity
  end

  def emit(entity, %Effects.HoverChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: true}, context) do
    Context.send_packet(context, %Message.SmsgMoveWaterWalk{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: false}, context) do
    Context.send_packet(context, %Message.SmsgMoveLandWalk{guid: guid})
    entity
  end

  def emit(entity, %Effects.WaterWalkChanged{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementSpeedChanged{speed: speed}, context)
      when is_number(speed) do
    Context.send_packet(context, %Message.SmsgForceRunSpeedChange{guid: guid, speed: speed})
    entity
  end

  def emit(entity, %Effects.MovementSpeedChanged{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.MonsterMove{move_opts: opts}, _context) do
    World.publish_movement(entity)
    notify_chasers(entity)

    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.MonsterMove{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.ChargeResolved{} = effect, context) do
    movement_block = %{
      entity.movement_block
      | spline_nodes: effect.path,
        duration: effect.duration_ms,
        spline_flags: 0x100
    }

    entity
    |> then(&%{&1 | movement_block: movement_block})
    |> Message.SmsgMonsterMove.build()
    |> World.broadcast_packet(entity)

    command = %Commands.ChargePathResolved{
      path: effect.path,
      duration_ms: effect.duration_ms,
      destination: effect.destination
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

  defp notify_chasers(%{object: %{guid: guid}, movement_block: %{position: {x, y, z, _o}}}) do
    ChaseWatch.notify_moved(guid, {x, y, z})
  end
end
