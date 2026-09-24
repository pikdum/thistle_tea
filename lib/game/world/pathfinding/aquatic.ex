defmodule ThistleTea.Game.World.Pathfinding.Aquatic do
  @moduledoc "Resolves underwater travel and checks creature habitat constraints against terrain and liquid surfaces."

  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World.Pathfinding

  @minimum_depth 1.5
  @surface_reach 2.0
  @floor_tolerance 0.5
  @sample_distance 3.0

  def water(map_id, {x, y, z} = position, minimum_depth \\ @minimum_depth) do
    with surface when is_number(surface) <- Pathfinding.query_liquid_surface(map_id, position),
         true <- z <= surface + @surface_reach,
         floor when is_number(floor) <- floor(map_id, {x, y}, z),
         true <- surface - floor > minimum_depth and z >= floor - @floor_tolerance do
      %{surface: surface, floor: floor}
    else
      _ -> nil
    end
  end

  def path(map_id, start, destination, opts, ground_path) do
    can_walk? = Keyword.get(opts, :can_walk?, true)
    can_swim? = Keyword.get(opts, :can_swim?, true)
    swim? = Keyword.get(opts, :swim_animation?, false)
    destination_water = water_for(map_id, destination, opts)

    cond do
      destination_water && not can_swim? ->
        nil

      is_nil(destination_water) and not can_walk? ->
        nil

      swim? and destination_water != nil ->
        underwater_path(map_id, start, beneath_surface(destination, destination_water.surface), opts, ground_path)

      true ->
        detour(map_id, start, destination, opts, ground_path)
    end
  end

  defp underwater_path(map_id, start, destination, opts, ground_path) do
    if water_segment?(map_id, start, destination, opts) and Pathfinding.collision_clear?(map_id, start, destination),
      do: [destination],
      else: detour(map_id, start, destination, opts, ground_path)
  end

  def random_point(map_id, {x, y, z} = anchor, radius, opts) do
    if Keyword.get(opts, :swim_animation?, false) and water_for(map_id, anchor, opts) != nil do
      angle = :rand.uniform() * 2 * :math.pi()
      distance = :rand.uniform() * radius
      point = {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z}

      with %{surface: surface, floor: floor} <- water_for(map_id, point, opts),
           {px, py, _} <- point,
           height = max(z, floor + @floor_tolerance),
           true <- height <= surface - 2.0 do
        {px, py, height}
      else
        _ -> nil
      end
    else
      Pathfinding.find_random_point_around_circle(map_id, anchor, radius)
    end
  end

  defp detour(map_id, start, destination, opts, ground_path) do
    case ground_path.(map_id, start, destination, opts) do
      [_ | _] = points ->
        points = finish_underwater(map_id, points, destination, opts)
        if permitted_path?(map_id, [start | points], opts) and clear_arrival?(map_id, points, opts), do: points

      _ ->
        nil
    end
  end

  defp clear_arrival?(map_id, points, opts) do
    case {Keyword.get(opts, :swim_animation?, false), Enum.take(points, -2)} do
      {true, [start, destination]} ->
        water_for(map_id, destination, opts) == nil or Pathfinding.collision_clear?(map_id, start, destination)

      _ ->
        true
    end
  end

  defp finish_underwater(map_id, points, destination, opts) do
    case {Keyword.get(opts, :swim_animation?, false), water_for(map_id, destination, opts)} do
      {true, %{surface: surface}} -> points ++ [beneath_surface(destination, surface)]
      _ -> points
    end
  end

  defp permitted_path?(map_id, points, opts) do
    can_walk? = Keyword.get(opts, :can_walk?, true)
    can_swim? = Keyword.get(opts, :can_swim?, true)

    (can_walk? and can_swim?) or
      points
      |> segments()
      |> Enum.flat_map(fn [start, destination] -> samples(start, destination) end)
      |> Enum.all?(fn point -> if water_for(map_id, point, opts), do: can_swim?, else: can_walk? end)
  end

  defp water_segment?(map_id, start, destination, opts),
    do: Enum.all?(samples(start, destination), &(water_for(map_id, &1, opts) != nil))

  defp water_for(map_id, position, opts), do: water(map_id, position, Keyword.get(opts, :minimum_depth, @minimum_depth))

  defp samples({sx, sy, sz} = start, {dx, dy, dz} = destination) do
    steps = max(ceil(Math.distance(start, destination) / @sample_distance), 1)

    for index <- 0..steps do
      fraction = index / steps
      {sx + (dx - sx) * fraction, sy + (dy - sy) * fraction, sz + (dz - sz) * fraction}
    end
  end

  defp segments(points), do: Enum.chunk_every(points, 2, 1, :discard)

  defp beneath_surface({x, y, z}, surface), do: {x, y, min(z, surface)}

  defp floor(map_id, position, z) do
    map_id
    |> Pathfinding.find_heights(position)
    |> Enum.filter(&(&1 <= z + @floor_tolerance))
    |> Enum.max(fn -> nil end)
  end
end
