defmodule ThistleTea.Game.Network.Message.CmsgFarSight do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_FAR_SIGHT

  defstruct [:operation]

  @impl ClientMessage
  def from_binary(<<operation::little-size(8)>>), do: %__MODULE__{operation: operation}
end
