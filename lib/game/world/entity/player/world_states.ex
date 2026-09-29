defmodule ThistleTea.Game.World.Entity.Player.WorldStates do
  @moduledoc """
  Initializes the client's map and zone world-state context after world entry.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.OutdoorPvp, as: OutdoorPvpSystem

  def initialize(%Character{} = character) do
    BattlegroundSystem.reconnect(character.object.guid, character.internal.world)
    send(self(), :refresh_outdoor_pvp)

    character
    |> build()
    |> Network.send_packet()
  end

  def build(
        %Character{
          internal: %Internal{world: %WorldRef{map_id: map_id}, area: area},
          movement_block: %MovementBlock{position: {x, y, z, _orientation}}
        } = character,
        zone_and_area \\ &Pathfinding.get_zone_and_area/2
      ) do
    zone =
      case zone_and_area.(map_id, {x, y, z}) do
        {zone, _area} when is_integer(zone) -> zone
        _ -> area || 0
      end

    states = BattlegroundSystem.world_states(character.internal.world) ++ OutdoorPvpSystem.world_states(zone)
    %Message.SmsgInitWorldStates{map: map_id, area: zone, states: states}
  end
end
