defmodule ThistleTea.Game.Inbound.CmsgLeaveChannel do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LEAVE_CHANNEL

  alias ThistleTea.Game.World.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  require Logger

  defstruct [:channel_name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, _} = BinaryUtils.parse_string(payload)

    %__MODULE__{
      channel_name: channel_name
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: channel_name}, state) do
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ChatChannels.leave(Chat.actor(state), channel_name)

    state
  end
end
