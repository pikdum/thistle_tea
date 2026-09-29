defmodule ThistleTea.Game.Network.Message.CmsgGuildDisband do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DISBAND

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.disband(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
