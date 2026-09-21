defmodule ThistleTea.Game.Entity.Logic.GameObjectInteraction do
  @moduledoc """
  Pure interaction preparation and geometry for scaled, rotated game objects.
  Display bounds expand by the interaction radius before world rotation.
  Objects without usable bounds use distance from their origin.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Mount

  def prepare_questgiver_use(%Character{} = character, %GameObjectTemplate{type: 2, data: data}, flags, now) do
    cond do
      ((flags || 0) &&& 0x10) != 0 ->
        {:error, :not_interactable}

      Enum.at(data, 5, 0) != 0 and ((character.unit.flags || 0) &&& 0x80000000) != 0 ->
        {:error, :immune}

      true ->
        {character, effects} = Aura.remove_with_interrupt_flags(character, 0x800, now)
        character = Effects.enqueue(character, effects)
        character = if Enum.at(data, 8, 0) == 0, do: Mount.dismount(character, now), else: character
        {:ok, character}
    end
  end

  def rotation({x, y, z, w}, orientation) when z == 0 and w == 0,
    do: {x, y, :math.sin(orientation / 2), :math.cos(orientation / 2)}

  def rotation(quaternion, _orientation), do: quaternion

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
