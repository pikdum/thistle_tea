defmodule ThistleTea.Game.Inbound.CmsgMoveWaterWalkAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_MOVE_WATER_WALK_ACK, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.State

  defstruct [:guid, :counter, :movement_payload, :apply]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), rest::binary>>) do
    info_size = byte_size(rest) - 4
    <<movement_payload::binary-size(^info_size), apply::little-size(32)>> = rest
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload, apply: apply}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %State{} = state),
    do: MovementControl.acknowledge_toggle(state, message.guid, message.counter, {:water_walk, message.apply != 0})
end
