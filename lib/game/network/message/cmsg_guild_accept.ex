defmodule ThistleTea.Game.Network.Message.CmsgGuildAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ACCEPT

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
