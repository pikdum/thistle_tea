defmodule ThistleTea.Game.Inbound.CmsgGuildLeader do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_LEADER

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.set_leader(state, name)
end
