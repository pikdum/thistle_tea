defmodule ThistleTea.Game.Network.Message.CmsgPetitionQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_QUERY

  defstruct [:petition_id, :item_guid]

  @impl ClientMessage
  def from_binary(<<id::little-size(32), guid::little-size(64), _rest::binary>>),
    do: %__MODULE__{petition_id: id, item_guid: guid}
end
