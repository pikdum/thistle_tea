defmodule ThistleTea.Game.Inbound.CmsgQuestgiverCompleteQuest do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUESTGIVER_COMPLETE_QUEST

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Quests

  defstruct [:guid, :quest_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), quest_id::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      quest_id: quest_id
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, quest_id: quest_id}, %{ready: true, character: %Character{}} = state) do
    Quests.complete_quest(state, guid, quest_id)
  end

  def handle(%__MODULE__{}, state), do: state
end
