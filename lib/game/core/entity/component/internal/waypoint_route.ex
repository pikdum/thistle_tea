defmodule ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute do
  @moduledoc """
  A mob's waypoint patrol route, tracking the current destination point and
  advancing through the loop. `World.Loader.Waypoint` builds it from
  `creature_movement` rows. The last point reached is where the mob returns
  after combat; until it reaches one, it returns to its spawn.
  """

  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint

  defstruct first_point: 0,
            destination_point: 0,
            last_point: nil,
            points: %{},
            repeat?: true,
            cyclic?: false,
            pathfind?: true

  def start(%__MODULE__{} = route, start_point, repeat?) when is_boolean(repeat?) do
    destination_point =
      if is_integer(start_point) and start_point > 0 and Map.has_key?(route.points, start_point) do
        start_point
      else
        route.first_point
      end

    %{route | destination_point: destination_point, last_point: nil, repeat?: repeat?}
  end

  def destination_waypoint(%__MODULE__{destination_point: id, points: points}) do
    Map.get(points, id)
  end

  def cycle_points(%__MODULE__{points: points}) when map_size(points) >= 2 do
    path =
      points
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_id, %Waypoint{position: {x, y, z, _}}} -> {x, y, z} end)

    if List.last(path) == hd(path), do: path, else: path ++ [hd(path)]
  end

  def cycle_points(%__MODULE__{}), do: []

  def increment_waypoint(%__MODULE__{first_point: first_point, destination_point: id, points: points} = route) do
    next_id = points |> Map.keys() |> Enum.filter(&(&1 > id)) |> Enum.min(fn -> nil end)
    next_id = next_id || if(route.repeat?, do: first_point)

    %{route | destination_point: next_id, last_point: id || route.last_point}
  end

  def reset_position(%__MODULE__{last_point: id, points: points}) do
    case Map.get(points, id) do
      %Waypoint{position: {x, y, z, _o}} -> {x, y, z}
      _unreached -> nil
    end
  end
end
