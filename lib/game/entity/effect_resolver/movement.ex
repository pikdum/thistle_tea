defmodule ThistleTea.Game.Entity.EffectResolver.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding

  @charge_speed 25.0

  def resolve(
        %Character{internal: %Internal{world: world}, movement_block: %{position: {x, y, z, _o}}},
        %Effects.Charge{target_guid: target_guid}
      ) do
    with {^world, tx, ty, tz} <- World.position(target_guid),
         path when is_list(path) and path != [] <- charge_path(world.map_id, {x, y, z}, {tx, ty, tz}) do
      duration_ms =
        [{x, y, z} | path]
        |> Math.movement_duration(@charge_speed)
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

  def resolve(%Character{internal: %Internal{world: world}} = entity, %Effects.Leap{position: {x, y, z, _o}}) do
    case clamp_leap_destination(entity, world.map_id, {x, y, z}) do
      {nx, ny, nz} -> [Effects.teleport_to_world(world, {nx, ny, nz})]
      nil -> []
    end
  end

  def resolve(_entity, %Effects.Leap{}), do: []

  def resolve(%Character{internal: %Internal{home_bind: {map, x, y, z}}}, %Effects.TeleportToSpellTarget{spell_id: 8690}) do
    [Effects.teleport_to_world(map, {x, y, z})]
  end

  def resolve(%Character{}, %Effects.TeleportToSpellTarget{spell_id: spell_id}) do
    case SpellLoader.target_position(spell_id) do
      %{map: map, x: x, y: y, z: z} -> [Effects.teleport_to_world(map, {x, y, z})]
      _missing -> []
    end
  end

  def resolve(_entity, %Effects.TeleportToSpellTarget{}), do: []

  defp charge_path(map, from, to) do
    Pathfinding.find_path(map, from, to, allow_steep: true)
  rescue
    _error -> nil
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
      _missing -> nil
    end
  rescue
    _error -> nil
  end

  defp clamp_leap_destination(_entity, _map, _position), do: nil

  defp snap_to_terrain_height(map, {x, y}, fallback_z, reference_z) do
    case Pathfinding.find_heights(map, {x, y}) do
      [] -> fallback_z
      heights -> Enum.min_by(heights, &abs(&1 - reference_z))
    end
  end
end
