defmodule ThistleTea.Game.World.Pathfinding do
  @moduledoc """
  Navigation-mesh queries over the namigator NIF: pathfinding, random points,
  terrain heights, and zone/area lookup.
  """
  alias ThistleTea.Native.Namigator

  def get_zone_and_area(map_id, {x, y, z}) do
    load_adt_at(map_id, {x, y})
    Namigator.get_zone_and_area(map_id, x, y, z)
  end

  def find_random_point_around_circle(map_id, {x, y, z}, radius) do
    load_adt_at(map_id, {x, y})
    Namigator.find_random_point_around_circle(map_id, x, y, z, radius)
  end

  def find_path(map_id, {start_x, start_y, start_z}, {stop_x, stop_y, stop_z}) do
    load_adt_at(map_id, {start_x, start_y})
    load_adt_at(map_id, {stop_x, stop_y})

    case Namigator.find_path(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z) do
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

  defp load_adt_at(map_id, {x, y}) do
    # TODO: store in :ets or similar, maybe with last access time, and unload periodically?
    Namigator.load_adt_at(map_id, x, y)
  end
end
