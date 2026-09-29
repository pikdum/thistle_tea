defmodule ThistleTea.Game.Core.GameObject.GameObjectInteraction do
  @moduledoc """
  Pure interaction preparation and geometry for scaled, rotated game objects.
  Display bounds expand by the interaction radius before world rotation.
  Objects without usable bounds use distance from their origin.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Invulnerability
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Movement.ControlMovement
  alias ThistleTea.Game.Core.OutdoorPvp.Silithyst
  alias ThistleTea.Game.Core.Spell.Mount

  def battleground_allowed?(%Character{} = character) do
    Death.alive?(character) and not Aura.has_spell?(character, 27_827) and
      (character.unit.mount_display_id || 0) == 0 and not Invulnerability.total?(character) and
      not ControlMovement.active?(character) and
      not Enum.any?([:mod_stun, :feign_death, :mod_possess], &Aura.has_aura?(character, &1))
  end

  def prepare_battleground_use(%Character{} = character, now) do
    if battleground_allowed?(character) do
      {character, effects} = Aura.remove_aura_types(character, [:mod_stealth, :mod_invisibility], now)
      {:ok, Effects.enqueue(character, effects)}
    else
      {:error, :not_interactable}
    end
  end

  def prepare_questgiver_use(%Character{} = character, %GameObjectTemplate{type: 2, data: data}, flags, now) do
    prepare_use(character, flags, Enum.at(data, 5, 0), Enum.at(data, 8, 0), now)
  end

  def prepare_readable_use(%Character{} = character, %GameObjectTemplate{type: 9, data: data}, flags, now) do
    prepare_use(character, flags, 0, Enum.at(data, 3, 0), now)
  end

  def prepare_readable_use(%Character{} = character, %GameObjectTemplate{type: 10, data: data} = template, flags, now) do
    if Silithyst.blocks_object?(character, template),
      do: {:error, :already_carrying},
      else: prepare_use(character, flags, Enum.at(data, 11, 0), Enum.at(data, 17, 0), now)
  end

  defp prepare_use(character, flags, no_damage_immune, allow_mounted, now) do
    cond do
      ((flags || 0) &&& 0x10) != 0 ->
        {:error, :not_interactable}

      no_damage_immune != 0 and ((character.unit.flags || 0) &&& 0x80000000) != 0 ->
        {:error, :immune}

      true ->
        {character, effects} = Aura.remove_with_interrupt_flags(character, 0x800, now)
        character = Effects.enqueue(character, effects)
        character = if allow_mounted == 0, do: Mount.dismount(character, now), else: character
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
