defmodule ThistleTea.Game.Network.Message.CmsgGuildQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_QUERY

  defstruct [:guild_id]

  @impl ClientMessage
  def from_binary(<<guild_id::little-size(32), _rest::binary>>), do: %__MODULE__{guild_id: guild_id}
end
