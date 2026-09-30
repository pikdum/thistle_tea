defmodule ThistleTea.Game.Inbound.CmsgMoveTimeSkipped do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_MOVE_TIME_SKIPPED
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_TIME_SKIPPED]

  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.State

  defstruct [:guid, :lag]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), lag::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      lag: lag
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, lag: lag}, %State{guid: guid} = state),
    do: MovementControl.time_skipped(state, lag)

  def handle(%__MODULE__{}, state), do: state
end
