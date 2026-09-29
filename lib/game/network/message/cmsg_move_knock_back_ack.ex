defmodule ThistleTea.Game.Network.Message.CmsgMoveKnockBackAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_KNOCK_BACK_ACK

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), movement_payload::binary>>) do
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload}
  end
end
