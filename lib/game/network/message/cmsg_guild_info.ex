defmodule ThistleTea.Game.Network.Message.CmsgGuildInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INFO

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
