defmodule ThistleTea.Game.Network.Message.SmsgChannelNotify do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHANNEL_NOTIFY

  @notice %{
    joined: 0x00,
    left: 0x01,
    you_joined: 0x02,
    you_left: 0x03,
    wrong_password: 0x04,
    not_member: 0x05,
    not_moderator: 0x06,
    password_changed: 0x07,
    owner_changed: 0x08,
    player_not_found: 0x09,
    not_owner: 0x0A,
    channel_owner: 0x0B,
    mode_change: 0x0C,
    announcements_on: 0x0D,
    announcements_off: 0x0E,
    moderation_on: 0x0F,
    moderation_off: 0x10,
    muted: 0x11,
    player_kicked: 0x12,
    banned: 0x13,
    player_banned: 0x14,
    player_unbanned: 0x15,
    player_not_banned: 0x16,
    player_already_member: 0x17,
    invite: 0x18,
    invite_wrong_faction: 0x19,
    wrong_faction: 0x1A,
    invalid_name: 0x1B,
    not_moderated: 0x1C,
    player_invited: 0x1D,
    player_invite_banned: 0x1E,
    throttled: 0x1F
  }

  def notice, do: @notice
  def notice(key), do: Map.fetch!(@notice, key)

  defstruct [
    :notify_type,
    :channel_name,
    :guid,
    :target_guid,
    :source_guid,
    :player_name,
    :owner_name,
    channel_flags: 0,
    channel_index: 0,
    old_flags: 0,
    new_flags: 0
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    <<msg.notify_type::little-size(8)>> <>
      msg.channel_name <>
      <<0>> <>
      notice_body(msg)
  end

  defp notice_body(%__MODULE__{notify_type: 0x02} = msg) do
    <<msg.channel_flags::little-size(32), msg.channel_index::little-size(32)>>
  end

  defp notice_body(%__MODULE__{notify_type: notify_type, guid: guid})
       when notify_type in [0x00, 0x01, 0x07, 0x08, 0x0D, 0x0E, 0x0F, 0x10, 0x17, 0x18] do
    <<guid::little-size(64)>>
  end

  defp notice_body(%__MODULE__{notify_type: 0x09, player_name: player_name}), do: player_name <> <<0>>
  defp notice_body(%__MODULE__{notify_type: 0x0B, owner_name: owner_name}), do: owner_name <> <<0>>

  defp notice_body(%__MODULE__{notify_type: 0x0C} = msg) do
    <<msg.guid::little-size(64), msg.old_flags::little-size(8), msg.new_flags::little-size(8)>>
  end

  defp notice_body(%__MODULE__{notify_type: notify_type} = msg) when notify_type in [0x12, 0x14, 0x15] do
    <<msg.target_guid::little-size(64), msg.source_guid::little-size(64)>>
  end

  defp notice_body(%__MODULE__{notify_type: notify_type, player_name: player_name})
       when notify_type in [0x16, 0x1D, 0x1E], do: player_name <> <<0>>

  defp notice_body(%__MODULE__{}), do: <<>>
end
