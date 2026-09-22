defmodule ThistleTea.Game.Network.Message.CmsgMoveKnockBackAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_KNOCK_BACK_ACK

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Knockback

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %State{} = state) do
    Knockback.acknowledge(state, message.guid, message.counter, message.movement_payload)
  end

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), movement_payload::binary>>) do
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload}
  end
end
