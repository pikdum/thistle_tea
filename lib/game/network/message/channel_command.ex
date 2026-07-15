defmodule ThistleTea.Game.Network.Message.ChannelCommand do
  @moduledoc false
  alias ThistleTea.Game.Network.BinaryUtils

  def parse_channel(payload) do
    {:ok, channel_name, _rest} = BinaryUtils.parse_string(payload)
    channel_name
  end

  def parse_target(payload) do
    {:ok, channel_name, rest} = BinaryUtils.parse_string(payload)
    {:ok, target_name, _rest} = BinaryUtils.parse_string(rest)
    {channel_name, target_name}
  end
end
