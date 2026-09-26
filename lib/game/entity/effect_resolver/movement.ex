defmodule ThistleTea.Game.Entity.EffectResolver.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Logic.Charge
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement, as: MovementLogic
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpellMovement

  def resolve(
        %{
          unit: %Unit{},
          internal: %Internal{world: world, taxi_flight: nil},
          movement_block: %{position: {x, y, z, _o}}
        } = entity,
        %Effects.Charge{target_guid: target_guid}
      ) do
    with false <- Core.dead?(entity) or MovementLogic.blocked?(entity) or target_guid == entity.object.guid,
         {^world, tx, ty, tz} <- World.position(target_guid),
         speed when speed > 0 <- min((entity.movement_block.run_speed || 7.0) * 4, 24.0),
         path when is_list(path) and path != [] <-
           charge_path(entity, target_guid, world.map_id, {x, y, z}, {tx, ty, tz}) do
      duration_ms =
        [{x, y, z} | path]
        |> Math.movement_duration(speed)
        |> Kernel.*(1_000)
        |> trunc()
        |> max(1)

      {dx, dy, dz} = List.last(path)
      destination = {dx, dy, dz, charge_facing({x, y}, {dx, dy})}
      [Effects.charge_resolved(path, duration_ms, destination)]
    else
      _no_path -> []
    end
  end

  def resolve(_entity, %Effects.Charge{}), do: []

  def resolve(%{unit: %Unit{}, internal: %Internal{world: world, taxi_flight: nil}} = entity, %Effects.Leap{
        position: {x, y, z, _o}
      }) do
    case clamp_leap_destination(entity, world.map_id, {x, y, z}) do
      {nx, ny, nz} -> [Effects.teleport_to_world(world, {nx, ny, nz}, preserve_combat?: true)]
      nil -> []
    end
  end

  def resolve(_entity, %Effects.Leap{}), do: []

  def resolve(
        %Character{internal: %Internal{home_bind: %HomeBind{map_id: map, position: position}}},
        %Effects.TeleportHome{}
      ) do
    [Effects.teleport_to_world(map, position)]
  end

  def resolve(_entity, %Effects.TeleportHome{}), do: []

  def resolve(%Character{}, %Effects.TeleportToSpellTarget{spell_id: spell_id}) do
    case SpellLoader.target_position(spell_id) do
      %{map: map, x: x, y: y, z: z} -> [Effects.teleport_to_world(map, {x, y, z})]
      _missing -> []
    end
  end

  def resolve(_entity, %Effects.TeleportToSpellTarget{}), do: []

  def resolve(
        %{internal: %Internal{world: world, taxi_flight: nil}},
        %Effects.TeleportNearCaster{caster_position: {world, _x, _y, _z}, caster_orientation: angle} = effect
      ) do
    case summon_destination(effect) do
      {x, y, z} ->
        orientation = :math.fmod(:math.fmod(-angle, 2 * :math.pi()) + 2 * :math.pi(), 2 * :math.pi())
        [Effects.teleport_to_world(world, {x, y, z}, preserve_combat?: true, orientation: orientation)]

      nil ->
        []
    end
  end

  def resolve(_entity, %Effects.TeleportNearCaster{}), do: []

  defp summon_destination(%Effects.TeleportNearCaster{destination: {:position, position}}), do: position

  defp summon_destination(
         %Effects.TeleportNearCaster{
           caster_position: {%{map_id: map}, _, _, _},
           destination: {:database, id, fallback_distance}
         } = effect
       ) do
    case SpellLoader.target_position(id) do
      %{map: ^map, x: x, y: y, z: z} -> {x, y, z}
      _missing -> summon_destination(%{effect | destination: {:forward, fallback_distance}})
    end
  end

  defp summon_destination(%Effects.TeleportNearCaster{
         caster_position: {%{map_id: map}, x, y, z},
         caster_orientation: angle,
         destination: {:forward, distance}
       }) do
    destination = {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z}
    Pathfinding.first_collision_position(map, {x, y, z}, destination)
  end

  defp charge_path(entity, target_guid, map, from, to) do
    metadata = Metadata.get(target_guid) || %{}

    reach =
      Combat.melee_reach(
        entity.unit.combat_reach || Unit.default_combat_reach(),
        Map.get(metadata, :combat_reach) || Unit.default_combat_reach()
      )

    with true <- Math.distance(from, to) > reach,
         path when is_list(path) <- Pathfinding.find_path(map, from, to, allow_steep: true) do
      Charge.approach_path(path, from, to, reach - 0.5)
    else
      _ -> nil
    end
  rescue
    _error -> nil
  end

  defp charge_facing({x, y}, {dx, dy}) when dx != x or dy != y do
    :math.atan2(dy - y, dx - x)
  end

  defp charge_facing(_from, _to), do: 0.0

  defp clamp_leap_destination(
         %{movement_block: %MovementBlock{position: {cx, cy, cz, _o}} = movement},
         map,
         destination
       ) do
    SpellMovement.leap_position(map, {cx, cy, cz}, destination, MovementBlock.falling_far?(movement))
  rescue
    _error -> nil
  end

  defp clamp_leap_destination(_entity, _map, _position), do: nil
end
