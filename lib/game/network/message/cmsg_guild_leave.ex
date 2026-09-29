defmodule ThistleTea.Game.Network.Message.CmsgGuildLeave do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_LEAVE

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
