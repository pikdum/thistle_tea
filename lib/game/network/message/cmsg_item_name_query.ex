defmodule ThistleTea.Game.Network.Message.CmsgItemNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ITEM_NAME_QUERY

  alias ThistleTea.Game.Network.Message

  defstruct [:item_id, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<item_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      item_id: item_id,
      guid: guid
    }
  end
end
