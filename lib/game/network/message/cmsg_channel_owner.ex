defmodule ThistleTea.Game.Network.Message.CmsgChannelOwner do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHANNEL_OWNER

  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.Network.Message.ChannelCommand
  alias ThistleTea.Game.World.System.ChatChannels

  defstruct [:channel_name]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: name}, state) do
    ChatChannels.owner(Chat.actor(state), name)
    state
  end

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{channel_name: ChannelCommand.parse_channel(payload)}
end
