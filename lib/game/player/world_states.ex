defmodule ThistleTea.Game.Player.WorldStates do
  @moduledoc """
  Initializes the client's map and zone world-state context after world entry.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.WorldRef

  def initialize(%Character{} = character) do
    character
    |> build()
    |> Network.send_packet()
  end

  def build(
        %Character{
          internal: %Internal{world: %WorldRef{map_id: map_id}, area: area},
          movement_block: %MovementBlock{position: {x, y, z, _orientation}}
        },
        zone_and_area \\ &Pathfinding.get_zone_and_area/2
      ) do
    zone =
      case zone_and_area.(map_id, {x, y, z}) do
        {zone, _area} when is_integer(zone) -> zone
        _ -> area || 0
      end

    %Message.SmsgInitWorldStates{map: map_id, area: zone, states: []}
  end
end
