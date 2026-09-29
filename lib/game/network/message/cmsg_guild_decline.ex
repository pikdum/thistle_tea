defmodule ThistleTea.Game.Network.Message.CmsgGuildDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DECLINE

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
