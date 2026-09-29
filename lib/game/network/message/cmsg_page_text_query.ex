defmodule ThistleTea.Game.Network.Message.CmsgPageTextQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PAGE_TEXT_QUERY

  defstruct [:page_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<page_id::little-size(32), _rest::binary>> = payload

    %__MODULE__{
      page_id: page_id
    }
  end
end
