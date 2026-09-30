defmodule ThistleTea.Game.Inbound.CmsgItemQuerySingle do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_ITEM_QUERY_SINGLE, while_possessed: true

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:item_id, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<item_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      item_id: item_id,
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{item_id: item_id}, state), do: item_id |> Queries.item() |> Query.reply(state)
end
