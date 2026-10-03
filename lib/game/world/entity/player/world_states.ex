defmodule ThistleTea.Game.World.Entity.Player.WorldStates do
  @moduledoc """
  Initializes the client's map and zone world-state context after world entry,
  and forwards the server-wide world states, such as the Scourge Invasion's
  map icons and tallies, that systems publish to every player.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.OutdoorPvp, as: OutdoorPvpSystem
  alias ThistleTea.Game.World.System.ScourgeInvasion, as: ScourgeInvasionSystem
  alias ThistleTea.Game.World.Topics

  def initialize(%Character{} = character) do
    BattlegroundSystem.reconnect(character.object.guid, character.internal.world)
    :ok = Topics.subscribe(Topics.world_states())
    send(self(), :refresh_outdoor_pvp)

    character
    |> build()
    |> Outbound.send_packet()
  end

  def update(states) when is_list(states) do
    Enum.each(states, fn {id, value} -> Outbound.send_packet(%Message.SmsgUpdateWorldState{state: id, value: value}) end)
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

    states =
      BattlegroundSystem.world_states(character.internal.world) ++
        OutdoorPvpSystem.world_states(zone) ++ ScourgeInvasionSystem.world_states()

    %Message.SmsgInitWorldStates{map: map_id, area: zone, states: states}
  end
end
