defmodule ThistleTea.Game.Network.Message.CmsgMoveNotActiveMover do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_NOT_ACTIVE_MOVER

  alias ThistleTea.Game.Player.Mover

  defstruct [:guid, :movement_payload]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, movement_payload: payload}, state), do: Mover.release(state, guid, payload)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), payload::binary>>), do: %__MODULE__{guid: guid, movement_payload: payload}
end
