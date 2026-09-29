defmodule ThistleTea.Game.Network.Message.CmsgGroupDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_DECLINE

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
