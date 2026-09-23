defmodule ThistleTea.Game.World.SpellMovement do
  @moduledoc """
  Resolves spell movement against walkable surfaces and collision geometry.
  """

  alias ThistleTea.Game.World.Pathfinding

  def leap_position(map, {sx, sy, sz} = origin, {dx, dy, _dz} = destination, falling?) do
    ground = ground_below(map, origin)
    surface = Pathfinding.query_liquid_surface(map, origin)

    position =
      cond do
        submerged?(sz, ground, surface) ->
          swim_destination(map, origin, destination) || Pathfinding.walk_hit_position(map, origin, destination)

        falling? and is_number(ground) and sz - ground <= 40.0 ->
          Pathfinding.walk_hit_position(map, {sx, sy, ground}, {dx, dy, ground})

        true ->
          Pathfinding.walk_hit_position(map, origin, destination)
      end

    if forward?(origin, destination, position), do: position
  end

  defp submerged?(z, ground, surface) when is_number(ground) and is_number(surface),
    do: surface > ground and z < surface

  defp submerged?(_z, _ground, _surface), do: false

  defp swim_destination(map, origin, destination) do
    {_x, _y, z} = position = Pathfinding.collision_position(map, origin, destination)

    case ground_below(map, position) do
      ground when is_number(ground) and ground < z -> position
      _missing -> nil
    end
  end

  defp ground_below(map, {x, y, z}) do
    map
    |> Pathfinding.find_heights({x, y})
    |> Enum.filter(&(&1 <= z + 0.1))
    |> Enum.max(fn -> nil end)
  end

  defp forward?({sx, sy, _sz}, {dx, dy, _dz}, {x, y, _z}) do
    forward = (x - sx) * (dx - sx) + (y - sy) * (dy - sy)
    sideways = (x - sx) * (dy - sy) - (y - sy) * (dx - sx)
    forward > 0 and abs(sideways) <= forward
  end

  defp forward?(_origin, _destination, _position), do: false
end
