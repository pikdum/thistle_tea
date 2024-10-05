defmodule ThistleTea.Pathfinding do
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
    Namigator.find_path(map_id, start_x, start_y, start_z, stop_x, stop_y, stop_z)
  end

  def find_point_between_points(
        map_id,
        {start_x, start_y, start_z},
        {stop_x, stop_y, stop_z},
        distance
      ) do
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
