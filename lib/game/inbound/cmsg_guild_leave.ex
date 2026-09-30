defmodule ThistleTea.Game.Inbound.CmsgGuildLeave do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_LEAVE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.leave(state)
end
