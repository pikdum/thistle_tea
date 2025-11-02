defmodule ThistleTea.Game.Network.Message.CmsgJoinChannel do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_JOIN_CHANNEL

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

  require Logger

  defstruct [:channel_name, :password]

  @impl ClientMessage
  def handle(%__MODULE__{channel_name: channel_name, password: _password}, state) do
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    with [] <- ThistleTea.ChatChannel |> Registry.values(channel_name, self()) do
      ThistleTea.ChatChannel
      |> Registry.register(channel_name, state.guid)

      Network.send_packet(%Message.SmsgChannelNotify{
        notify_type: 0x02,
        channel_name: channel_name
      })
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, rest} = Util.parse_string(payload)
    {:ok, password, _} = Util.parse_string(rest)

    %__MODULE__{
      channel_name: channel_name,
      password: password
    }
  end
end
