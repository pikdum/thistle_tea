defmodule ThistleTea.Game.Network.Message.CmsgZoneupdate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ZONEUPDATE

  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Pathfinding

  defstruct [:area]

  @impl ClientMessage
  def handle(%__MODULE__{area: client_zone}, %{ready: true, character: %Character{} = character} = state) do
    %{internal: %{world: world, area: current_area}} = character
    {x, y, z, _o} = character.movement_block.position

    {state, server_zone} =
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

    zone = server_zone || client_zone

    state =
      if is_integer(zone) and zone > 0 do
        PlayerRest.update_zone(state, zone)
      else
        state
      end

    PlayerExploration.check_current(state)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    case payload do
      <<area::little-size(32)>> -> %__MODULE__{area: area}
      _ -> %__MODULE__{}
    end
  end
end
