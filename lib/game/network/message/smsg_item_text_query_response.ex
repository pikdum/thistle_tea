defmodule ThistleTea.Game.Network.Message.SmsgItemTextQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ITEM_TEXT_QUERY_RESPONSE

  defstruct item_text_id: 0, text: ""

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.item_text_id::little-size(32)>> <> message.text <> <<0>>
  end
end
