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
    %{internal: %{map: map, area: current_area}} = character
    {x, y, z, _o} = character.movement_block.position

    state =
      case Pathfinding.get_zone_and_area(map, {x, y, z}) do
        {_zone, area} when area != current_area ->
          character = %{character | internal: %{character.internal | area: area}}
          CharacterStore.put(character)
          PartyNotifier.broadcast_stats(state.guid, character)
          %{state | character: character}

        _ ->
          state
      end

    state =
      if is_integer(client_zone) and client_zone > 0 do
        PlayerRest.update_zone(state, client_zone)
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
