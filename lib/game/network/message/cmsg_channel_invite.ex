defmodule ThistleTea.Game.Network.Message.CmsgChannelInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHANNEL_INVITE

  alias ThistleTea.Game.Network.Message.ChannelCommand

  defstruct [:channel_name, :player_name]

  @impl ClientMessage
  def from_binary(payload) do
    {channel_name, player_name} = ChannelCommand.parse_target(payload)
    %__MODULE__{channel_name: channel_name, player_name: player_name}
  end
end
