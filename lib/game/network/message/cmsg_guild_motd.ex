defmodule ThistleTea.Game.Network.Message.CmsgGuildMotd do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_MOTD

  defstruct [:motd]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, motd, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{motd: motd}
  end
end
