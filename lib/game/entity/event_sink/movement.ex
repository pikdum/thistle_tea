defmodule ThistleTea.Game.Entity.EventSink.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding

  @charge_speed 25.0

  def emit(%Mob{} = entity, %Effects.MovementStopped{}) do
    World.update_position(entity)
    World.clear_movement(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Effects.MovementStopped{}) do
    World.update_position(entity)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: true}) do
    Network.send_packet(%Message.SmsgForceMoveRoot{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementRootChanged{rooted?: false}) do
    Network.send_packet(%Message.SmsgForceMoveUnroot{guid: guid})
    entity
  end

  def emit(entity, %Effects.MovementRootChanged{}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveFeatherFall{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.FeatherFallChanged{enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveNormalFall{guid: guid})
    entity
  end

  def emit(entity, %Effects.FeatherFallChanged{}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveSetHover{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.HoverChanged{enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveUnsetHover{guid: guid})
    entity
  end

  def emit(entity, %Effects.HoverChanged{}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: true}) do
    Network.send_packet(%Message.SmsgMoveWaterWalk{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.WaterWalkChanged{enabled?: false}) do
    Network.send_packet(%Message.SmsgMoveLandWalk{guid: guid})
    entity
  end

  def emit(entity, %Effects.WaterWalkChanged{}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.MovementSpeedChanged{speed: speed})
      when is_number(speed) do
    Network.send_packet(%Message.SmsgForceRunSpeedChange{guid: guid, speed: speed})
    entity
  end

  def emit(entity, %Effects.MovementSpeedChanged{}), do: entity

  def emit(%Mob{} = entity, %Effects.MonsterMove{move_opts: opts}) do
    World.publish_movement(entity)
    notify_chasers(entity)

    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.MonsterMove{}), do: entity

  def emit(
        %Character{internal: %Internal{world: world}, movement_block: %{position: {x, y, z, _o}}} = entity,
        %Effects.Charge{target_guid: target_guid}
      ) do
    with {^world, tx, ty, tz} <- World.position(target_guid),
         path when is_list(path) and path != [] <- charge_path(world.map_id, {x, y, z}, {tx, ty, tz}) do
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

  def emit(entity, %Effects.Charge{}), do: entity

  def emit(%Character{internal: %Internal{world: world}} = entity, %Effects.Teleport{position: {x, y, z, o}}) do
    GenServer.cast(self(), {:start_teleport, x, y, z, o, world})
    entity
  end

  def emit(entity, %Effects.Teleport{}), do: entity

  def emit(%Character{internal: %Internal{world: world}} = entity, %Effects.Leap{position: {x, y, z, _o}}) do
    case clamp_leap_destination(entity, world.map_id, {x, y, z}) do
      {nx, ny, nz} -> GenServer.cast(self(), {:start_teleport, nx, ny, nz, world})
      nil -> nil
    end

    entity
  end

  def emit(entity, %Effects.Leap{}), do: entity

  def emit(%Character{internal: %Internal{home_bind: {map, x, y, z}}} = entity, %Effects.TeleportToSpellTarget{
        spell_id: 8690
      }) do
    GenServer.cast(self(), {:start_teleport, x, y, z, map})
    entity
  end

  def emit(%Character{} = entity, %Effects.TeleportToSpellTarget{spell_id: spell_id}) do
    case SpellLoader.target_position(spell_id) do
      %{map: map, x: x, y: y, z: z} -> GenServer.cast(self(), {:start_teleport, x, y, z, map})
      _ -> nil
    end

    entity
  end

  def emit(entity, %Effects.TeleportToSpellTarget{}), do: entity

  def emit(entity, %Effects.SetFacing{facing: facing}) do
    Message.SmsgMonsterMove.build_face(entity, facing)
    |> World.broadcast_packet(entity)

    entity
  end

  defp notify_chasers(%{object: %{guid: guid}, movement_block: %{position: {x, y, z, _o}}}) do
    ChaseWatch.notify_moved(guid, {x, y, z})
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
end
