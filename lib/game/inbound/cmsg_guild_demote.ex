defmodule ThistleTea.Game.Inbound.CmsgGuildDemote do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_DEMOTE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.demote(state, name)
end
