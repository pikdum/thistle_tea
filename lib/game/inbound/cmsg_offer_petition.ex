defmodule ThistleTea.Game.Inbound.CmsgOfferPetition do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_OFFER_PETITION

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:item_guid, :target_guid]

  @impl ClientMessage
  def from_binary(<<item_guid::little-size(64), target_guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{item_guid: item_guid, target_guid: target_guid}

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: item_guid, target_guid: target_guid}, state),
    do: Petitions.offer(state, item_guid, target_guid)
end
