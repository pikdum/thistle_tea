defmodule ThistleTea.Game.Inbound.CmsgGuildRemove do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_REMOVE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Guilds.remove(state, name)
end
