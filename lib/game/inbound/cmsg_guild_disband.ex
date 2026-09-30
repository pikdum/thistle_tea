defmodule ThistleTea.Game.Inbound.CmsgGuildDisband do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_DISBAND

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.disband(state)
end
