defmodule ThistleTea.Game.Network.Message.CmsgLeaveChannel do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEAVE_CHANNEL

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

  require Logger

  defstruct [:channel_name]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: channel_name}, state) do
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ThistleTea.ChatChannel
    |> Registry.unregister(channel_name)

    Network.send_packet(%Message.SmsgChannelNotify{
      notify_type: 0x03,
      channel_name: channel_name
    })

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, _} = Util.parse_string(payload)

    %__MODULE__{
      channel_name: channel_name
    }
  end
end
