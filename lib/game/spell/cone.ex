defmodule ThistleTea.Game.Spell.Cone do
  @moduledoc "Pure cone geometry, including configured forward arcs and negative rear arcs."

  def contains?(degrees, {x, y, _z, orientation}, {tx, ty, _tz}) when is_number(degrees) do
    angle = :math.atan2(ty - y, tx - x) - orientation
    angle = abs(:math.atan2(:math.sin(angle), :math.cos(angle)))

    cond do
      degrees > 0 -> angle <= degrees * :math.pi() / 360
      degrees < 0 -> angle > (360 + degrees) * :math.pi() / 360
      true -> false
    end
  end

  def contains?(_degrees, _caster, _target), do: false
end
