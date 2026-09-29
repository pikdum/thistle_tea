defmodule ThistleTea.Game.Network.Message.CmsgLeaveChannel do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LEAVE_CHANNEL

  defstruct [:channel_name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, channel_name, _} = BinaryUtils.parse_string(payload)

    %__MODULE__{
      channel_name: channel_name
    }
  end
end
