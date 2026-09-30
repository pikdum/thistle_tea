defmodule ThistleTea.Game.Inbound.CmsgGuildRoster do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_ROSTER

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.roster(state)
end
