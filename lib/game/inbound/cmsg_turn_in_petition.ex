defmodule ThistleTea.Game.Inbound.CmsgTurnInPetition do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_TURN_IN_PETITION

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.turn_in(state, guid)
end
