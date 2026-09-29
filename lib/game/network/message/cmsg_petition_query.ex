defmodule ThistleTea.Game.Network.Message.CmsgPetitionQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_QUERY

  alias ThistleTea.Game.Player.Petitions

  defstruct [:petition_id, :item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{petition_id: id, item_guid: guid}, state), do: Petitions.query(state, id, guid)

  @impl ClientMessage
  def from_binary(<<id::little-size(32), guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{petition_id: id, item_guid: guid}
end
