defmodule ThistleTea.Game.Network.Message.MsgQuestPushResultClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_QUEST_PUSH_RESULT

  defstruct [:guid, :result]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), result::little-size(8)>>), do: %__MODULE__{guid: guid, result: result}
end
