defmodule ThistleTea.Game.Inbound.CmsgChannelOwner do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHANNEL_OWNER

  alias ThistleTea.Game.Inbound.ChannelCommand
  alias ThistleTea.Game.World.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  defstruct [:channel_name]

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{channel_name: ChannelCommand.parse_channel(payload)}

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: name}, state) do
    ChatChannels.owner(Chat.actor(state), name)
    state
  end
end
