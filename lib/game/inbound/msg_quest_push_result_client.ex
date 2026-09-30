defmodule ThistleTea.Game.Inbound.MsgQuestPushResultClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_QUEST_PUSH_RESULT

  alias ThistleTea.Game.World.Entity.Player.QuestSharing

  defstruct [:guid, :result]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), result::little-size(8)>>), do: %__MODULE__{guid: guid, result: result}

  @impl ClientMessage
  def handle(%__MODULE__{result: result}, state), do: QuestSharing.result(state, result)
end
