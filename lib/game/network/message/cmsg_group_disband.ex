defmodule ThistleTea.Game.Network.Message.CmsgGroupDisband do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_DISBAND

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
