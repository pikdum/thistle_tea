defmodule ThistleTea.Game.Network.Message.CmsgJoinChannel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_JOIN_CHANNEL

  defstruct [:channel_name, :password]

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
