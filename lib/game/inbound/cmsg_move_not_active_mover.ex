defmodule ThistleTea.Game.Inbound.CmsgMoveNotActiveMover do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_MOVE_NOT_ACTIVE_MOVER, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Mover

  defstruct [:guid, :movement_payload]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), payload::binary>>), do: %__MODULE__{guid: guid, movement_payload: payload}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, movement_payload: payload}, state), do: Mover.release(state, guid, payload)
end
