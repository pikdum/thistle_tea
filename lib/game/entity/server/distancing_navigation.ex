defmodule ThistleTea.Game.Entity.Server.DistancingNavigation do
  @moduledoc "Validates target-relative retreats before replacing movement or interrupting a cast."

  alias ThistleTea.Game.Entity.Logic.AI.BT.Distancing
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World.Pathfinding

  def resolve(entity, intent, now, find_path, geometry \\ []) do
    memory = entity.internal.blackboard.distancing

    if memory && memory.destination == intent.destination do
      resolve_current(entity, memory, now, find_path, geometry)
    else
      entity
    end
  end

  defp resolve_current(entity, memory, now, find_path, geometry) do
    map = entity.internal.world.map_id
    {x, y, z, _} = entity.movement_block.position
    start = {x, y, z}
    snap = Keyword.get(geometry, :snap_to_ground, &Pathfinding.snap_to_ground/2)
    visible? = Keyword.get(geometry, :line_of_sight?, &Pathfinding.line_of_sight?/3)
    destination = ground_destination(entity, memory.destination, snap)

    with true <- Distancing.allowed?(entity),
         true <- elem(destination, 2) <= z + 10.0 and Math.distance(start, destination) > 0.1,
         true <- visible?.(map, memory.target_position, destination),
         [_ | _] = path <- find_path.(map, start, destination, path_options(entity)),
         true <- NavigationIntent.reached?(List.last(path), destination) do
      Distancing.accept(entity, path, now)
    else
      _ -> Distancing.reject(entity)
    end
  end

  defp ground_destination(entity, destination, snap) do
    if CreatureMovement.flying?(entity) or CreatureMovement.swims?(entity),
      do: destination,
      else: snap.(entity.internal.world.map_id, destination)
  end

  defp path_options(entity) do
    [allow_steep: true, flying?: CreatureMovement.flying?(entity)] ++ NavigationResolver.path_options(entity)
  end
end
