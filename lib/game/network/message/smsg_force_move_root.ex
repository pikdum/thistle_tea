defmodule ThistleTea.Game.Network.Message.SmsgForceMoveRoot do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FORCE_MOVE_ROOT

  defstruct [:guid, move_event: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, move_event: move_event}) do
    BinaryUtils.pack_guid(guid) <> <<move_event::little-size(32)>>
  end
end
