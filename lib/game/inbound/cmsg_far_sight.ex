defmodule ThistleTea.Game.Inbound.CmsgFarSight do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_FAR_SIGHT, while_possessed: true

  alias ThistleTea.Game.World.Visibility

  defstruct [:operation]

  @impl ClientMessage
  def from_binary(<<operation::little-size(8)>>), do: %__MODULE__{operation: operation}

  @impl ClientMessage
  def handle(%__MODULE__{operation: operation}, state), do: Visibility.select_viewpoint(state, operation)
end
