defmodule ThistleTea.Game.Network.Message.CmsgQuestQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUEST_QUERY

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<quest_id::little-size(32)>> = payload

    %__MODULE__{
      quest_id: quest_id
    }
  end
end
