defmodule ThistleTea.Game.Inbound.CmsgGuildQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_QUERY

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:guild_id]

  @impl ClientMessage
  def from_binary(<<guild_id::little-size(32), _rest::binary>>), do: %__MODULE__{guild_id: guild_id}

  @impl ClientMessage
  def handle(%__MODULE__{guild_id: id}, state), do: Guilds.query(state, id)
end
