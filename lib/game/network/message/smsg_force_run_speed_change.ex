defmodule ThistleTea.Game.Network.Message.SmsgForceRunSpeedChange do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FORCE_RUN_SPEED_CHANGE

  defstruct [:guid, :speed, move_event: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, speed: speed, move_event: move_event}) do
    BinaryUtils.pack_guid(guid) <> <<move_event::little-size(32), speed::little-float-size(32)>>
  end
end
