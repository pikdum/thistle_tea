defmodule ThistleTea.Game.World.Entity.Player.Zone do
  @moduledoc """
  Resolves the player's zone and area from terrain when the client reports a
  zone change, falling back to the client's zone. A new area is stored and
  shared with the party; the zone drives rest state, outdoor PvP, and
  exploration.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.World.Entity.Player.OutdoorPvp
  alias ThistleTea.Game.World.Entity.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Party.Notifier, as: PartyNotifier

  def update(%{character: %Character{} = character} = state, client_zone) do
    {state, server_zone} = resolve(state, character)
    zone = server_zone || client_zone
    state = if is_integer(zone) and zone > 0, do: PlayerRest.update_zone(state, zone), else: state

    state
    |> OutdoorPvp.refresh(server_zone)
    |> PlayerExploration.check_current()
  end

  defp resolve(state, %Character{internal: %{world: world, area: current_area}} = character) do
    {x, y, z, _o} = character.movement_block.position

    case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
      {zone, area} when area != current_area ->
        character = %{character | internal: %{character.internal | area: area}}
        CharacterStore.put(character)
        PartyNotifier.broadcast_stats(state.guid, character)
        {%{state | character: character}, zone}

      {zone, _area} ->
        {state, zone}

      _unknown ->
        {state, PlayerRest.default_zone(world.map_id)}
    end
  end
end
