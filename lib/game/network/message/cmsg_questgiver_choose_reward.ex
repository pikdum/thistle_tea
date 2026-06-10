defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverChooseReward do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_CHOOSE_REWARD

  alias ThistleTea.Game.Player.Quests

  defstruct [:guid, :quest_id, :reward_index]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{}} = state) do
    Quests.choose_reward(state, message.guid, message.quest_id, message.reward_index)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), quest_id::little-size(32), reward_index::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      quest_id: quest_id,
      reward_index: reward_index
    }
  end
end
