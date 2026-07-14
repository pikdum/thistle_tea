defmodule ThistleTea.Game.Network.Message.CmsgForceMoveRootAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FORCE_MOVE_ROOT_ACK

  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Session

  defstruct [:guid, :counter, :movement_payload]

  @impl ClientMessage
  def handle(
        %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload},
        %Session{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state
      ) do
    case MovementControl.acknowledge(state, guid, counter, :root) do
      {:ok, state} ->
        movement_block = MovementBlock.from_binary(movement_payload, movement_block)

        MovementControl.maybe_finish_repop(%{state | character: %{character | movement_block: movement_block}})

      {:error, state} ->
        state
    end
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
