defmodule ThistleTea.Game.Inbound.CmsgChannelList do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHANNEL_LIST

  alias ThistleTea.Game.Inbound.ChannelCommand
  alias ThistleTea.Game.World.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  defstruct [:channel_name]

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{channel_name: ChannelCommand.parse_channel(payload)}

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: name}, state) do
    ChatChannels.list(Chat.actor(state), name)
    state
  end
end
