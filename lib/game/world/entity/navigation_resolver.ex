defmodule ThistleTea.Game.World.Entity.NavigationResolver do
  @moduledoc """
  Resolves navigation intents at the entity-owner boundary. A creature headed
  home that has no path there, such as one left in the air or knocked off the
  mesh, takes the straight line, as the vmangos path finder's shortcut does.
  """

  alias ThistleTea.Game.Core.AI.NavigationIntent
  alias ThistleTea.Game.Core.Combat.UnreachableTarget
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.World.Entity.DistancingNavigation
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Pathfinding

  def resolve(entity, now, find_path \\ &Pathfinding.find_path/4)

  def resolve(%{internal: %Internal{}, movement_block: %MovementBlock{}} = entity, now, find_path)
      when is_integer(now) and is_function(find_path, 4) do
    {entity, intents} = NavigationIntent.drain(entity)
    Enum.reduce(intents, entity, &resolve_intent(&2, &1, now, find_path))
  end

  def resolve(entity, _now, _find_path), do: entity

  def path_options(entity) do
    case CreatureMovement.path_options(entity) do
      [] ->
        []

      opts ->
        Keyword.put(
          opts,
          :minimum_depth,
          ModelGeometry.height(entity.unit.display_id) * (entity.object.scale_x || 1.0) * 0.75
        )
    end
  end

  defp resolve_intent(entity, %NavigationIntent{opts: opts} = intent, now, find_path) do
    if Keyword.get(opts, :distancing?, false),
      do: DistancingNavigation.resolve(Movement.sync_position(entity, now), intent, now, find_path),
      else: resolve_path(entity, intent, now, find_path)
  end

  defp resolve_path(
         %{internal: %Internal{world: world}} = entity,
         %NavigationIntent{destination: destination, path: requested_path, opts: opts},
         now,
         find_path
       ) do
    entity = Movement.sync_position(entity, now)
    flying? = Keyword.get(opts, :flying?, CreatureMovement.flying?(entity))
    {start_x, start_y, start_z, _orientation} = entity.movement_block.position

    {allow_steep, opts} = Keyword.pop(opts, :allow_steep, true)
    {max_distance, opts} = Keyword.pop(opts, :max_distance)
    {within_radius, opts} = Keyword.pop(opts, :within_radius)
    {pathfind?, opts} = Keyword.pop(opts, :pathfind?, true)
    {shortcut?, opts} = Keyword.pop(opts, :shortcut?, false)
    {chase_target, opts} = Keyword.pop(opts, :chase_target)
    start = {start_x, start_y, start_z}
    opts = travel_velocity(opts, start, destination)
    entity = replace_point_movement(entity, opts, now)
    path_opts = if flying?, do: [allow_steep: allow_steep, flying?: true], else: [allow_steep: allow_steep]
    path_opts = path_opts ++ path_options(entity)

    path =
      cond do
        is_list(requested_path) -> requested_path
        pathfind? -> shortcut(find_path.(world.map_id, start, destination, path_opts), shortcut?, destination)
        true -> [destination]
      end

    case path do
      path when is_list(path) ->
        path = path |> limit_path(start, max_distance) |> within_radius(start, within_radius)
        opts = arrival_velocity(opts, [start | path], now)
        opts = completion_options(opts, path, destination)

        entity
        |> UnreachableTarget.record(chase_target, NavigationIntent.reached?(List.last(path) || start, destination), now)
        |> Movement.move_along_path(path, opts, now)

      _no_path ->
        UnreachableTarget.record(entity, chase_target, false, now)
    end
  end

  defp shortcut(nil, true, destination), do: [destination]
  defp shortcut(path, _shortcut?, _destination), do: path

  defp replace_point_movement(entity, opts, now) do
    if Keyword.has_key?(opts, :movement_inform), do: Movement.stop(entity, now), else: entity
  end

  defp completion_options(opts, path, destination) do
    case List.last(path) do
      {_, _, _} = endpoint ->
        if NavigationIntent.reached?(endpoint, destination), do: opts, else: Keyword.delete(opts, :movement_inform)

      nil ->
        Keyword.delete(opts, :movement_inform)
    end
  end

  defp travel_velocity(opts, start, destination) do
    {duration, opts} = Keyword.pop(opts, :travel_time)

    if is_integer(duration) and duration > 0,
      do: Keyword.put(opts, :velocity, Math.distance(start, destination) * 1_000 / duration),
      else: opts
  end

  defp arrival_velocity(opts, path, now) do
    {deadline, opts} = Keyword.pop(opts, :arrive_at)
    {maximum, opts} = Keyword.pop(opts, :max_velocity)

    if is_integer(deadline) and is_number(maximum) and maximum > 0 do
      distance = Math.movement_duration(path, 1.0)
      velocity = min(distance * 1_000 / max(deadline - now, 1), maximum)
      if velocity > 0, do: Keyword.put(opts, :velocity, velocity), else: opts
    else
      opts
    end
  end

  defp within_radius(path, _start, nil), do: path

  defp within_radius(path, start, {anchor, radius}) do
    if Enum.all?([start | path], &(Math.distance(anchor, &1) <= radius + 0.01)), do: path, else: []
  end

  defp limit_path(path, _start, nil), do: path
  defp limit_path([], _start, _remaining), do: []
  defp limit_path(_path, _start, remaining) when remaining <= 0, do: []

  defp limit_path([{x, y, z} = point | rest], {sx, sy, sz} = start, remaining) do
    distance = Math.distance(start, point)

    if distance <= remaining do
      [point | limit_path(rest, point, remaining - distance)]
    else
      fraction = remaining / distance
      [{sx + (x - sx) * fraction, sy + (y - sy) * fraction, sz + (z - sz) * fraction}]
    end
  end
end
