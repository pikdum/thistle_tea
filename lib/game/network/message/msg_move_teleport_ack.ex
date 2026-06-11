defmodule ThistleTea.Game.Network.Message.MsgMoveTeleportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MOVE_TELEPORT_ACK

  defstruct [:guid, :position, counter: 0, movement_flags: 0, timestamp: 0, fall_time: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, position: {x, y, z, o}} = m) do
    BinaryUtils.pack_guid(guid) <>
      <<
        m.counter::little-size(32),
        m.movement_flags::little-size(32),
        m.timestamp::little-size(32),
        x::little-float-size(32),
        y::little-float-size(32),
        z::little-float-size(32),
        o::little-float-size(32),
        m.fall_time::little-size(32)
      >>
  end
end
