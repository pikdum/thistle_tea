defmodule ThistleTea.Game.Network.Message.CmsgItemNameQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ITEM_NAME_QUERY

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct [:item_id, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_id: item_id, guid: _guid}, state) do
    item = Mangos.Repo.get(Mangos.ItemTemplate, item_id)
    Logger.info("CMSG_ITEM_NAME_QUERY: #{item.name}")

    Network.send_packet(%Message.SmsgItemNameQueryResponse{
      item_id: item_id,
      item_name: item.name
    })

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<item_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      item_id: item_id,
      guid: guid
    }
  end
end
