defmodule ThistleTea.Game.Inbound.CmsgMoveKnockBackAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_MOVE_KNOCK_BACK_ACK, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Knockback
  alias ThistleTea.Game.World.Entity.Player.State

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), movement_payload::binary>>) do
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %State{} = state) do
    Knockback.acknowledge(state, message.guid, message.counter, message.movement_payload)
  end
end
