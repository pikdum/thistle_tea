defmodule ThistleTea.Game.Inbound.CmsgNpcTextQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_NPC_TEXT_QUERY, while_possessed: true

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:text_id, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<text_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      text_id: text_id,
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{text_id: text_id}, state), do: text_id |> Queries.npc_text() |> Query.reply(state)
end
