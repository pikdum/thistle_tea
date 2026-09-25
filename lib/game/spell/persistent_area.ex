defmodule ThistleTea.Game.Spell.PersistentArea do
  @moduledoc """
  Identifies a ground aura's source, footprint, and fixed lifetime. Recipients
  retain its periodic schedule while the boundary checks source availability.
  """

  alias ThistleTea.Game.Math

  @enforce_keys [:guid, :position, :radius, :started_at, :expires_at]
  defstruct [:guid, :position, :radius, :started_at, :expires_at]

  def contains?(%__MODULE__{position: {world, x, y, z}, radius: radius}, {world, tx, ty, tz}) do
    Math.distance({x, y, z}, {tx, ty, tz}) <= radius
  end

  def contains?(_area, _position), do: false

  def next_tick(%__MODULE__{started_at: started_at}, interval, now) when is_integer(interval) and interval > 0 do
    started_at + (div(max(now - started_at, 0), interval) + 1) * interval
  end
end
