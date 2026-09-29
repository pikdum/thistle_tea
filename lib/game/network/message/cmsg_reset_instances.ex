defmodule ThistleTea.Game.Network.Message.CmsgResetInstances do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RESET_INSTANCES

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
