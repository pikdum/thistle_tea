defmodule ThistleTea.Game.Inbound.CmsgGuildMotd do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_MOTD

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:motd]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, motd, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{motd: motd}
  end

  @impl ClientMessage
  def handle(%__MODULE__{motd: motd}, state), do: Guilds.set_motd(state, motd)
end
