defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverChooseReward do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_CHOOSE_REWARD

  defstruct [:guid, :quest_id, :reward_index]

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
