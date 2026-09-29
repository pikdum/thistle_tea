defmodule ThistleTea.Game.Network.Message.CmsgGuildDisband do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DISBAND

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
