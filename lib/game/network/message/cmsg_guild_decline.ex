defmodule ThistleTea.Game.Network.Message.CmsgGuildDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DECLINE

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.decline(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
