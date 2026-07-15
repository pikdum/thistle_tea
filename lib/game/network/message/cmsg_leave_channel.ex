defmodule ThistleTea.Game.Network.Message.CmsgLeaveChannel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEAVE_CHANNEL

  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  require Logger

  defstruct [:channel_name]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: channel_name}, state) do
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ChatChannels.leave(Chat.actor(state), channel_name)

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, _} = BinaryUtils.parse_string(payload)

    %__MODULE__{
      channel_name: channel_name
    }
  end
end
