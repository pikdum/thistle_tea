defmodule ThistleTea.Game.Network.Message.CmsgItemQuerySingle do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ITEM_QUERY_SINGLE

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  require Logger

  defstruct [:item_id, :guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_id: item_id, guid: _guid}, state) do
    Logger.info("CMSG_ITEM_QUERY_SINGLE: #{item_id}")

    item = ItemLoader.get_template(item_id)

    Network.send_packet(%Message.SmsgItemQuerySingleResponse{
      item_id: item_id,
      item: item
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
