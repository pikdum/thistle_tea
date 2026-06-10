defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverRequestReward do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_REQUEST_REWARD

  alias ThistleTea.Game.Player.Quests

  defstruct [:guid, :quest_id]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, quest_id: quest_id}, %{ready: true, character: %Character{}} = state) do
    Quests.request_reward(state, guid, quest_id)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), quest_id::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      quest_id: quest_id
    }
  end
end
