defmodule ThistleTea.Game.Network.Message.CmsgGuildInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_INVITE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.invite(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
