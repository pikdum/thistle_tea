defmodule ThistleTea.Game.Inbound.CmsgPetitionShowSignatures do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PETITION_SHOW_SIGNATURES

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.show_signatures(state, guid)
end
