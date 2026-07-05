defmodule ThistleTea.Game.Network.Message.CmsgPageTextQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PAGE_TEXT_QUERY

  alias ThistleTea.Game.World.Loader.PageText, as: PageTextLoader

  @missing_page_text "Item page missing."

  defstruct [:page_id]

  @impl ClientMessage
  def handle(%__MODULE__{page_id: page_id}, state) do
    send_pages(page_id, MapSet.new())
    state
  end

  defp send_pages(page_id, seen) when is_integer(page_id) and page_id > 0 do
    if MapSet.member?(seen, page_id) do
      :ok
    else
      next_page = send_page(page_id)
      send_pages(next_page, MapSet.put(seen, page_id))
    end
  end

  defp send_pages(_page_id, _seen), do: :ok

  defp send_page(page_id) do
    case PageTextLoader.get(page_id) do
      %{text: text, next_page: next_page} ->
        Network.send_packet(%Message.SmsgPageTextQueryResponse{page_id: page_id, text: text, next_page: next_page})
        next_page

      nil ->
        Network.send_packet(%Message.SmsgPageTextQueryResponse{page_id: page_id, text: @missing_page_text})
        0
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<page_id::little-size(32), _rest::binary>> = payload

    %__MODULE__{
      page_id: page_id
    }
  end
end
