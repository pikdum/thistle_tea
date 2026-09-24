defmodule ThistleTea.Game.Network.Message.CmsgFarSight do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FAR_SIGHT

  alias ThistleTea.Game.World.Visibility

  defstruct [:operation]

  @impl ClientMessage
  def handle(%__MODULE__{operation: operation}, state), do: Visibility.select_viewpoint(state, operation)

  @impl ClientMessage
  def from_binary(<<operation::little-size(8)>>), do: %__MODULE__{operation: operation}
end
