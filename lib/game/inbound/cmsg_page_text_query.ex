defmodule ThistleTea.Game.Inbound.CmsgPageTextQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PAGE_TEXT_QUERY

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:page_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<page_id::little-size(32), _rest::binary>> = payload

    %__MODULE__{
      page_id: page_id
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{page_id: page_id}, state), do: page_id |> Queries.pages() |> Query.reply(state)
end
