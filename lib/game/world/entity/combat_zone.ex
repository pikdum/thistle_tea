defmodule ThistleTea.Game.World.Entity.CombatZone do
  @moduledoc "Captures players and their combat pets in the creature's exact dungeon copy."

  alias ThistleTea.Game.Core.AI.BT.Context.CombatZone
  alias ThistleTea.Game.Core.Combat.ZoneCombat
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata

  def snapshot(%Mob{internal: %{world: world}} = entity, true) do
    if ZoneCombat.eligible?(entity) and MapTemplate.dungeon?(world.map_id) do
      players = world |> World.players_in() |> Enum.sort()
      pets = players |> Enum.flat_map(&pet/1) |> Map.new()
      %CombatZone{world: world, players: players, pets: pets}
    end
  end

  def snapshot(_entity, _requested?), do: nil

  defp pet(player) do
    with %{controlled_guid: guid} when is_integer(guid) and guid > 0 <- Metadata.get(player),
         %{owner_guid: ^player, pet_kind: kind} when kind in [:hunter, :summon] <- Metadata.get(guid) do
      [{player, guid}]
    else
      _ -> []
    end
  end
end
