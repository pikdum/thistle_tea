defmodule ThistleTea.Game.Network.Message.CmsgPushquesttoparty do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PUSHQUESTTOPARTY

  alias ThistleTea.Game.Player.QuestSharing

  defstruct [:quest_id]

  @impl ClientMessage
  def from_binary(<<quest_id::little-size(32)>>), do: %__MODULE__{quest_id: quest_id}

  @impl ClientMessage
  def handle(%__MODULE__{quest_id: quest_id}, state), do: QuestSharing.share(state, quest_id)
end
