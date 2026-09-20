defmodule ThistleTea.Game.Network.Message.CmsgMoveSplineDone do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_SPLINE_DONE

  alias ThistleTea.Game.Player.Taxi

  defstruct [:movement_block, :spline_id, :unknown]

  @impl ClientMessage
  def handle(%__MODULE__{spline_id: spline_id}, state), do: Taxi.spline_done(state, spline_id)

  @impl ClientMessage
  def from_binary(payload) do
    movement_size = byte_size(payload) - 8

    <<movement_payload::binary-size(^movement_size), spline_id::little-size(32), unknown::little-float-size(32)>> =
      payload

    %__MODULE__{movement_block: MovementBlock.from_binary(movement_payload), spline_id: spline_id, unknown: unknown}
  end
end
