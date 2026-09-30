defmodule ThistleTea.Game.Inbound.CmsgPetitionQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PETITION_QUERY

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:petition_id, :item_guid]

  @impl ClientMessage
  def from_binary(<<id::little-size(32), guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{petition_id: id, item_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{petition_id: id, item_guid: guid}, state), do: Petitions.query(state, id, guid)
end
