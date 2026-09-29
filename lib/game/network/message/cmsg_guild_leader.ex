defmodule ThistleTea.Game.Network.Message.CmsgGuildLeader do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_LEADER

  alias ThistleTea.Game.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.set_leader(state, name)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end
end
