defmodule ThistleTea.Game.Network.Message.SmsgPageTextQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PAGE_TEXT_QUERY_RESPONSE

  defstruct [:page_id, :text, next_page: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{page_id: page_id, text: text, next_page: next_page}) do
    <<page_id::little-size(32)>> <> text <> <<0>> <> <<next_page::little-size(32)>>
  end
end
