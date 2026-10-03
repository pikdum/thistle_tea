defmodule ThistleTea.Game.World.Entity.EffectResolver.LocalDefense do
  @moduledoc """
  Turns the death of a town guard or PvP-flagging creature into a
  LocalDefense alert when a player, or a creature they control, killed it.
  The alert carries the creature's area, or its zone where the area is
  unknown, and the killer's team.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Honor
  alias ThistleTea.Game.Core.LocalDefense
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Combat.KillReward
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  def resolve(entity, effect, opts \\ [])

  def resolve(%Mob{} = victim, %Effects.CreatureDefeated{source_guid: source_guid}, opts) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid, :race]))
    area_of = Keyword.get(opts, :area_of, &area_of/2)

    with true <- LocalDefense.defender?(victim),
         player when is_integer(player) <- KillReward.controlling_player(source_guid, metadata),
         %{race: race} <- metadata.(player),
         team when team in [:alliance, :horde] <- Honor.team(race),
         %WorldRef{} = world <- victim.internal.world,
         area_id when is_integer(area_id) <- area_of.(world, victim.movement_block.position) do
      [%Effects.LocalDefenseAlert{world: world, area_id: area_id, attacking_team: team}]
    else
      _not_alerted -> []
    end
  end

  def resolve(_entity, %Effects.CreatureDefeated{}, _opts), do: []

  defp area_of(%WorldRef{map_id: map_id}, {x, y, z, _orientation}) do
    case Pathfinding.get_zone_and_area(map_id, {x, y, z}) do
      {_zone, area} when is_integer(area) and area > 0 -> area
      {zone, _area} when is_integer(zone) and zone > 0 -> zone
      _unknown -> nil
    end
  end
end
