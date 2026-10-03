defmodule ThistleTea.Game.World.Entity.Mob.NecropolisHealth do
  @moduledoc """
  Counts a fallen necropolis against its zone's Scourge Invasion
  (vmangos `NecropolisHealthAI::JustDied`). A necropolis falls when its
  health dies to the third death bolt from the camps beneath it.
  """

  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.ScourgeInvasion, as: ScourgeInvasionSystem

  @necropolis_health 16_421

  def fell(%Mob{object: %{entry: @necropolis_health}, movement_block: %{position: {x, y, z, _o}}} = state) do
    case Pathfinding.get_zone_and_area(state.internal.world.map_id, {x, y, z}) do
      {zone, _area} when is_integer(zone) -> ScourgeInvasionSystem.necropolis_fell(zone)
      _unknown -> :ok
    end

    state
  end

  def fell(state), do: state
end
