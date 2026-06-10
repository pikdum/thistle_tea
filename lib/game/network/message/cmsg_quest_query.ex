defmodule ThistleTea.Game.Network.Message.CmsgQuestQuery do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUEST_QUERY

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  defstruct [:quest_id]

  @impl ClientMessage
  def handle(%__MODULE__{quest_id: quest_id}, state) do
    case QuestLoader.get(quest_id) do
      %Quest{} = quest ->
        Network.send_packet(%Message.SmsgQuestQueryResponse{quest: quest})

      nil ->
        :ok
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<quest_id::little-size(32)>> = payload

    %__MODULE__{
      quest_id: quest_id
    }
  end
end
