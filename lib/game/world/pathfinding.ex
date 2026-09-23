defmodule ThistleTea.Game.World.Pathfinding do
  @moduledoc """
  Navigation-mesh queries over the namigator NIF: pathfinding, random points,
  terrain and liquid heights, and zone/area lookup.
  """
  alias ThistleTea.Game.Math
  alias ThistleTea.Native.Namigator

  @area_floor_tolerance 0.1
  @area_surface_distance 3.0

  def get_zone_and_area(map_id, {x, y, z}) do
    load_adt_at(map_id, {x, y})

    case Namigator.get_zone_and_area(map_id, x, y, z) do
      {_zone, area} = result when area > 0 -> result
      _unknown -> surface_zone_and_area(map_id, {x, y, z})
    end
  end

  defp surface_zone_and_area(map_id, {x, y, z}) do
    map_id
    |> find_heights({x, y})
    |> Enum.filter(&(abs(&1 - z) <= @area_surface_distance))
    |> Enum.sort_by(&abs(&1 - z))
    |> Enum.find_value(fn height ->
      case Namigator.get_zone_and_area(map_id, x, y, height - @area_floor_tolerance) do
        {_zone, area} = result when area > 0 -> result
        _unknown -> nil
      end
    end)
  end

  def find_random_point_around_circle(map_id, {x, y, z}, radius) do
    load_adt_at(map_id, {x, y})
    Namigator.find_random_point_around_circle(map_id, x, y, z, radius)
  end

  def find_path(map_id, {start_x, start_y, start_z}, {stop_x, stop_y, stop_z}, opts \\ []) do
    load_adt_at(map_id, {start_x, start_y})
    load_adt_at(map_id, {stop_x, stop_y})

    allow_steep? = Keyword.get(opts, :allow_steep, false)

    case Namigator.find_path(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z, allow_steep?) do
      [_first | [_second | _rest] = path] -> path
      path -> path
    end
  end

  def find_heights(map_id, {x, y}) do
    load_adt_at(map_id, {x, y})

    case Namigator.find_heights(map_id, x, y) do
      heights when is_list(heights) -> heights
      _ -> []
    end
  end

  def walk_hit_position(map_id, {sx, sy, sz}, {dx, dy, dz}) do
    load_adt_at(map_id, {sx, sy})
    load_adt_at(map_id, {dx, dy})
    Namigator.walk_hit_position(map_id, sx, sy, sz, dx, dy, dz)
  end

  def snap_to_ground(map_id, {x, y, z}) do
    case find_heights(map_id, {x, y}) do
      [_ | _] = heights -> {x, y, ground_height(heights, z)}
      _ -> {x, y, z}
    end
  end

  defp ground_height(heights, z) do
    case Enum.filter(heights, &(&1 <= z)) do
      [_ | _] = below -> Enum.max(below)
      [] -> Enum.min_by(heights, &abs(&1 - z))
    end
  end

  def query_liquid_surface(map_id, {x, y, z}) do
    load_adt_at(map_id, {x, y})
    Namigator.query_liquid_surface(map_id, x, y, z)
  end

  @los_source_eye_height 2.0
  @los_target_eye_height 1.0

  def line_of_sight?(map_id, {start_x, start_y, start_z}, {stop_x, stop_y, stop_z}) do
    load_adt_at(map_id, {start_x, start_y})
    load_adt_at(map_id, {stop_x, stop_y})

    case Namigator.line_of_sight(
           map_id,
           start_x,
           start_y,
           start_z + @los_source_eye_height,
           stop_x,
           stop_y,
           stop_z + @los_target_eye_height
         ) do
      visible? when is_boolean(visible?) -> visible?
      _unknown -> true
    end
  end

  def find_point_between_points(map_id, {start_x, start_y, start_z}, {stop_x, stop_y, stop_z}, distance) do
    Namigator.find_point_between_points(
      map_id,
      start_x,
      start_y,
      start_z,
      stop_x,
      stop_y,
      stop_z,
      distance
    )
  end

  def first_collision_position(map_id, origin, destination) do
    destination = nearest_ground(map_id, destination)

    if line_of_sight?(map_id, origin, destination) do
      destination
    else
      clear_segment(map_id, origin, destination, 0.0, 1.0, 10)
    end
  end

  def collision_position(map_id, {sx, sy, _sz} = origin, {dx, dy, _dz} = destination) do
    load_adt_at(map_id, {sx, sy})
    load_adt_at(map_id, {dx, dy})

    if collision_clear?(map_id, origin, destination) do
      destination
    else
      fraction = collision_fraction(map_id, origin, destination, 0.0, 1.0, 14)
      distance = Math.distance(origin, destination)
      interpolate(origin, destination, max(0.0, fraction - 0.5 / max(distance, 0.001)))
    end
  end

  defp collision_fraction(_map_id, _origin, _destination, clear, _blocked, 0), do: clear

  defp collision_fraction(map_id, origin, destination, clear, blocked, steps) do
    fraction = (clear + blocked) / 2

    if collision_clear?(map_id, origin, interpolate(origin, destination, fraction)),
      do: collision_fraction(map_id, origin, destination, fraction, blocked, steps - 1),
      else: collision_fraction(map_id, origin, destination, clear, fraction, steps - 1)
  end

  defp collision_clear?(map_id, {sx, sy, sz}, {dx, dy, dz}),
    do: Namigator.line_of_sight(map_id, sx, sy, sz, dx, dy, dz, true) != false

  defp clear_segment(map_id, origin, destination, clear, _blocked, 0),
    do: nearest_ground(map_id, interpolate(origin, destination, clear))

  defp clear_segment(map_id, origin, destination, clear, blocked, steps) do
    fraction = (clear + blocked) / 2
    candidate = nearest_ground(map_id, interpolate(origin, destination, fraction))

    if line_of_sight?(map_id, origin, candidate),
      do: clear_segment(map_id, origin, destination, fraction, blocked, steps - 1),
      else: clear_segment(map_id, origin, destination, clear, fraction, steps - 1)
  end

  defp nearest_ground(map_id, {x, y, z}) do
    height = map_id |> find_heights({x, y}) |> Enum.min_by(&abs(&1 - z), fn -> z end)
    {x, y, height}
  end

  defp interpolate({x, y, z}, {dx, dy, dz}, fraction),
    do: {x + (dx - x) * fraction, y + (dy - y) * fraction, z + (dz - z) * fraction}

  defp load_adt_at(map_id, {x, y}) do
    # TODO: store in :ets or similar, maybe with last access time, and unload periodically?
    Namigator.load_adt_at(map_id, x, y)
  end
end
