defmodule ThistleTea.Game.Network.Message.CmsgChannelAnnouncements do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHANNEL_ANNOUNCEMENTS

  alias ThistleTea.Game.Network.Message.ChannelCommand

  defstruct [:channel_name]

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{channel_name: ChannelCommand.parse_channel(payload)}
end
