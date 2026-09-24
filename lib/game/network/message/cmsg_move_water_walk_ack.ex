defmodule ThistleTea.Game.Network.Message.CmsgMoveWaterWalkAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_WATER_WALK_ACK

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.MovementControl

  defstruct [:guid, :counter, :movement_payload, :apply]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %State{} = state) do
    case MovementControl.acknowledge(state, message.guid, message.counter, {:water_walk, message.apply != 0}) do
      {:ok, state} -> MovementControl.maybe_finish_repop(state)
      {:error, state} -> state
    end
  end

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), counter::little-size(32), rest::binary>>) do
    info_size = byte_size(rest) - 4
    <<movement_payload::binary-size(^info_size), apply::little-size(32)>> = rest
    %__MODULE__{guid: guid, counter: counter, movement_payload: movement_payload, apply: apply}
  end
end
