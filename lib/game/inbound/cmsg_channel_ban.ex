defmodule ThistleTea.Game.Inbound.CmsgChannelBan do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHANNEL_BAN

  alias ThistleTea.Game.Inbound.ChannelCommand
  alias ThistleTea.Game.World.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  defstruct [:channel_name, :player_name]

  @impl ClientMessage
  def from_binary(payload) do
    {channel_name, player_name} = ChannelCommand.parse_target(payload)
    %__MODULE__{channel_name: channel_name, player_name: player_name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: name, player_name: player_name}, state) do
    ChatChannels.ban(Chat.actor(state), name, player_name)
    state
  end
end
