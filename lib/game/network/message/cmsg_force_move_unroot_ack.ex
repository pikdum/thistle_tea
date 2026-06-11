defmodule ThistleTea.Game.Network.Message.CmsgForceMoveUnrootAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FORCE_MOVE_UNROOT_ACK

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def handle(
        %__MODULE__{movement_payload: movement_payload},
        %{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state
      ) do
    movement_block = MovementBlock.from_binary(movement_payload, movement_block)
    %{state | character: %{character | movement_block: movement_block}}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), counter::little-size(32), movement_payload::binary>> = payload

    %__MODULE__{
      guid: guid,
      counter: counter,
      movement_payload: movement_payload
    }
  end
end
