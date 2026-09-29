defmodule ThistleTea.Game.Network.Message.MsgMoveTimeSkipped do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MOVE_TIME_SKIPPED

  defstruct [:guid, lag: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, lag: lag}) do
    BinaryUtils.pack_guid(guid) <> <<lag::little-size(32)>>
  end
end
