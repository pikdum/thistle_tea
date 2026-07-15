defmodule ThistleTea.Game.Network.Message.CmsgChannelUnmoderator do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHANNEL_UNMODERATOR

  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.Network.Message.ChannelCommand
  alias ThistleTea.Game.World.System.ChatChannels

  defstruct [:channel_name, :player_name]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_moderator(Chat.actor(state), name, player_name, false)
    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    {channel_name, player_name} = ChannelCommand.parse_target(payload)
    %__MODULE__{channel_name: channel_name, player_name: player_name}
  end
end
