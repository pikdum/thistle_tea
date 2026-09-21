defmodule ThistleTea.Game.Entity.Logic.GameObjectInteraction do
  @moduledoc """
  Pure interaction geometry for scaled, rotated game objects.
  Display bounds expand by the interaction radius before world rotation.
  Objects without usable bounds use distance from their origin.
  """

  def within?(position, origin, rotation, scale, bounds, radius)

  def within?({x, y, z} = position, {ox, oy, oz} = origin, rotation, scale, {_, _} = bounds, radius)
      when is_number(scale) and scale > 0 do
    if has_bounds?(bounds) do
      local = inverse_rotate({x - ox, y - oy, z - oz}, rotation)
      bounds_contain?(local, scale, bounds, radius)
    else
      within?(position, origin, rotation, scale, nil, radius)
    end
  end

  def within?({x, y, z}, {ox, oy, oz}, _rotation, _scale, _bounds, radius) do
    dx = x - ox
    dy = y - oy
    dz = z - oz
    dx * dx + dy * dy + dz * dz <= radius * radius
  end

  defp has_bounds?({{lx, ly, lz}, {hx, hy, hz}}), do: Enum.any?([lx, ly, lz, hx, hy, hz], &(&1 != 0))

  defp bounds_contain?({x, y, z}, scale, {{lx, ly, lz}, {hx, hy, hz}}, radius) do
    x >= lx * scale - radius and x <= hx * scale + radius and
      y >= ly * scale - radius and y <= hy * scale + radius and
      z >= lz * scale - radius and z <= hz * scale + radius
  end

  defp inverse_rotate({x, y, z}, {qx, qy, qz, qw}) do
    norm = qx * qx + qy * qy + qz * qz + qw * qw

    if norm > 0 do
      tx = 2 * (qz * y - qy * z) / norm
      ty = 2 * (qx * z - qz * x) / norm
      tz = 2 * (qy * x - qx * y) / norm

      {x + qw * tx + qz * ty - qy * tz, y + qw * ty + qx * tz - qz * tx, z + qw * tz + qy * tx - qx * ty}
    else
      {x, y, z}
    end
  end
end
