defmodule ThistleTea.Game.Inbound.CmsgQuestConfirmAccept do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_QUEST_CONFIRM_ACCEPT

  alias ThistleTea.Game.World.Entity.Player.QuestSharing

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(<<quest_id::little-size(32)>>), do: %__MODULE__{quest_id: quest_id}

  @impl ClientMessage
  def handle(%__MODULE__{quest_id: quest_id}, state), do: QuestSharing.confirm(state, quest_id)
end
