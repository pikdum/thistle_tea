defmodule ThistleTea.Game.Inbound.CmsgForceMoveRootAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_FORCE_MOVE_ROOT_ACK, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.State

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), movement_payload::binary>> = payload

    %__MODULE__{
      guid: guid,
      counter: counter,
      movement_payload: movement_payload
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %State{} = state),
    do: MovementControl.acknowledge_controlled(state, message.guid, message.counter, :root, message.movement_payload)
end
