defmodule ThistleTea.Game.World.Entity.Mob.Flight do
  @moduledoc "Resolves the ground beneath a flying corpse at its owning boundary."

  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.World.Pathfinding

  def land_corpse(%Mob{} = mob, now, find_heights \\ &Pathfinding.find_heights/2) do
    if CreatureMovement.can_fly?(mob) do
      mob = Movement.sync_position(mob, now)
      {x, y, z, _orientation} = mob.movement_block.position

      floor =
        mob.internal.world.map_id
        |> find_heights.({x, y})
        |> Enum.filter(&(&1 <= z))
        |> Enum.max(fn -> z end)

      Movement.fall_to(mob, floor, now)
    else
      mob
    end
  end
end
