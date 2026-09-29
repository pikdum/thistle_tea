defmodule ThistleTea.Game.Network.Message.CmsgChannelPassword do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHANNEL_PASSWORD

  alias ThistleTea.Game.Network.Message.ChannelCommand

  defstruct [:channel_name, :password]

  @impl ClientMessage
  def from_binary(payload) do
    {channel_name, password} = ChannelCommand.parse_target(payload)
    %__MODULE__{channel_name: channel_name, password: password}
  end
end
