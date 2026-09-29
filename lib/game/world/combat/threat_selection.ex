defmodule ThistleTea.Game.World.Combat.ThreatSelection do
  @moduledoc """
  Victim-selection callbacks for `Core.Combat.Threat.reselect/2` when a mob
  reselects outside its behavior-tree tick (entering combat from a hit or
  dropping a threat entry). Candidates must be on the mob's map and valid
  attack targets; melee range combines both combat reaches.
  """
  alias ThistleTea.Game.Core.Combat
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Reaction

  def opts(%Mob{} = mob), do: [valid?: &valid_target?(mob, &1), in_melee?: &in_melee_range?(mob, &1)]

  defp valid_target?(%Mob{internal: %Internal{world: world}} = mob, guid) do
    case World.position(guid) do
      {^world, _x, _y, _z} -> Reaction.valid_attack_target?(mob, guid)
      _ -> false
    end
  end

  defp in_melee_range?(%Mob{} = mob, guid) do
    case World.distance_between(mob, guid) do
      distance when is_number(distance) ->
        distance <= Combat.melee_reach(own_combat_reach(mob), target_combat_reach(guid))

      _ ->
        false
    end
  end

  defp own_combat_reach(%Mob{unit: %Unit{combat_reach: reach}}) when is_number(reach) and reach > 0, do: reach
  defp own_combat_reach(%Mob{}), do: Unit.default_combat_reach()

  defp target_combat_reach(guid) do
    case Metadata.query(guid, [:combat_reach]) do
      %{combat_reach: reach} when is_number(reach) -> reach
      _ -> Unit.default_combat_reach()
    end
  end
end
