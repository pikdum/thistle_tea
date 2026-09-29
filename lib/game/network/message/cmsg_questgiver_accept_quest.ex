defmodule ThistleTea.Game.Network.Message.CmsgQuestgiverAcceptQuest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUESTGIVER_ACCEPT_QUEST

  defstruct [:guid, :quest_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), quest_id::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      quest_id: quest_id
    }
  end
end
