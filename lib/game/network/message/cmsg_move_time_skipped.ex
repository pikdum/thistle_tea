defmodule ThistleTea.Game.Network.Message.CmsgMoveTimeSkipped do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_TIME_SKIPPED
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_TIME_SKIPPED]

  defstruct [:guid, :lag]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), lag::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      lag: lag
    }
  end
end
