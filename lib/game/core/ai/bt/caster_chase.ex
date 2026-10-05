defmodule ThistleTea.Game.Core.AI.BT.CasterChase do
  @moduledoc "A scripted caster's stopping range and approach position, including flight altitude."

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Math

  def distance(%Mob{internal: %{creature: %Creature{caster_chase_distance: distance}}})
      when is_number(distance) and distance > 0, do: distance

  def distance(%Mob{}), do: nil

  def in_range?(
        %Mob{unit: %{target: guid}, internal: %{world: world}, movement_block: %{position: {x, y, z, _}}} = mob,
        %Context{perception: perception}
      ) do
    with radius when is_number(radius) <- distance(mob),
         {^world, tx, ty, tz} <- Perception.position(perception, guid) do
      Math.distance({x, y, z}, {tx, ty, tz}) <= radius + 0.01 and Perception.line_of_sight?(perception, guid)
    else
      _unavailable -> false
    end
  end

  def destination(%Mob{movement_block: %{position: {x, y, z, _}}} = mob, {tx, ty, tz}) do
    radius = distance(mob)
    source = if CreatureMovement.can_fly?(mob), do: {x, y, z}, else: {x, y, tz}
    approach(source, {tx, ty, tz}, radius)
  end

  defp approach({sx, sy, sz} = source, {tx, ty, tz} = target, radius) do
    separation = Math.distance(source, target)

    if separation > radius do
      ratio = radius / separation
      {tx + (sx - tx) * ratio, ty + (sy - ty) * ratio, tz + (sz - tz) * ratio}
    else
      source
    end
  end
end
