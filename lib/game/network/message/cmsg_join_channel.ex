defmodule ThistleTea.Game.Network.Message.CmsgJoinChannel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_JOIN_CHANNEL

  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.World.System.ChatChannels

  require Logger

  defstruct [:channel_name, :password]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: channel_name, password: password}, state) do
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    ChatChannels.join(Chat.actor(state), channel_name, password)

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, rest} = BinaryUtils.parse_string(payload)
    {:ok, password, _} = BinaryUtils.parse_string(rest)

    %__MODULE__{
      channel_name: channel_name,
      password: password
    }
  end
end
