defmodule ThistleTea.Game.Network.Message.CmsgGuildDelRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_DEL_RANK

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
