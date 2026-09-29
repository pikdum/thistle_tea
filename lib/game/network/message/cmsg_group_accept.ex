defmodule ThistleTea.Game.Network.Message.CmsgGroupAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_ACCEPT

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
