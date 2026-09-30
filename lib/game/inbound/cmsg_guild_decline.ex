defmodule ThistleTea.Game.Inbound.CmsgGuildDecline do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_DECLINE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.decline(state)
end
