defmodule ThistleTea.Game.Network.Message.CmsgMoveWaterWalkAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_WATER_WALK_ACK

  defstruct [:guid, :counter, :movement_payload, :apply]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), rest::binary>>) do
    info_size = byte_size(rest) - 4
    <<movement_payload::binary-size(^info_size), apply::little-size(32)>> = rest
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload, apply: apply}
  end
end
