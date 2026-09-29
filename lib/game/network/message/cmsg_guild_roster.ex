defmodule ThistleTea.Game.Network.Message.CmsgGuildRoster do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_ROSTER

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
