defmodule ThistleTea.Game.Message.SmsgItemNameQueryResponse do
  use ThistleTea.Game.ServerMessage, :SMSG_ITEM_NAME_QUERY_RESPONSE

  defstruct [
    :item_id,
    :item_name
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        item_id: item_id,
        item_name: item_name
      }) do
    <<item_id::little-size(32)>> <> item_name <> <<0>>
  end
end
