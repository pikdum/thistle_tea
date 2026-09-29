defmodule ThistleTea.Game.Network.Message.CmsgGuildDelRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DEL_RANK

  alias ThistleTea.Game.Player.Guilds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Guilds.delete_rank(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
