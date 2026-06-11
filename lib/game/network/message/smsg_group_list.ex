defmodule ThistleTea.Game.Network.Message.SmsgGroupList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GROUP_LIST

  @master_loot 2

  defstruct group_type: 0,
            own_flags: 0,
            members: [],
            leader: 0,
            loot_method: 0,
            master_looter: 0,
            loot_threshold: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    members =
      Enum.map_join(msg.members, fn member ->
        member.name <>
          <<0, member.guid::little-size(64), online_byte(member)::little-size(8), member.flags::little-size(8)>>
      end)

    looter = if msg.loot_method == @master_loot, do: msg.master_looter, else: 0

    <<msg.group_type::little-size(8), msg.own_flags::little-size(8), length(msg.members)::little-size(32)>> <>
      members <>
      <<msg.leader::little-size(64), msg.loot_method::little-size(8), looter::little-size(64),
        msg.loot_threshold::little-size(8)>>
  end

  defp online_byte(%{online?: true}), do: 1
  defp online_byte(_member), do: 0
end
