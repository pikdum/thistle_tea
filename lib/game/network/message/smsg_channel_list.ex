defmodule ThistleTea.Game.Network.Message.SmsgChannelList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHANNEL_LIST

  defstruct [:channel_name, channel_flags: 0, members: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    members =
      Enum.map_join(msg.members, fn member ->
        <<member.guid::little-size(64), member.flags::little-size(8)>>
      end)

    msg.channel_name <>
      <<0, msg.channel_flags::little-size(8), length(msg.members)::little-size(32)>> <>
      members
  end
end
