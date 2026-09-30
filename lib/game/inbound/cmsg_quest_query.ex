defmodule ThistleTea.Game.Inbound.CmsgQuestQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_QUEST_QUERY, while_possessed: true

  alias ThistleTea.Game.Inbound.Query
  alias ThistleTea.Game.World.Entity.Player.Queries

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<quest_id::little-size(32)>> = payload

    %__MODULE__{
      quest_id: quest_id
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{quest_id: quest_id}, state), do: quest_id |> Queries.quest() |> Query.reply(state)
end
