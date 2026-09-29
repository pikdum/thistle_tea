defmodule ThistleTea.Game.Network.Message.CmsgOfferPetition do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_OFFER_PETITION

  defstruct [:item_guid, :target_guid]

  @impl ClientMessage
  def from_binary(<<item_guid::little-size(64), target_guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{item_guid: item_guid, target_guid: target_guid}
end
