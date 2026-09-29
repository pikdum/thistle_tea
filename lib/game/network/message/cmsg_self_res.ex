defmodule ThistleTea.Game.Network.Message.CmsgSelfRes do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SELF_RES

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
