defmodule ThistleTea.Game.Network.Message.CmsgQuestConfirmAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_QUEST_CONFIRM_ACCEPT

  alias ThistleTea.Game.Player.QuestSharing

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(<<quest_id::little-size(32)>>), do: %__MODULE__{quest_id: quest_id}

  @impl ClientMessage
  def handle(%__MODULE__{quest_id: quest_id}, state), do: QuestSharing.confirm(state, quest_id)
end
