defmodule ThistleTea.Game.Message.SmsgChannelNotify do
  use ThistleTea.Game.ServerMessage, :SMSG_CHANNEL_NOTIFY

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
  def noitce(key), do: Map.fetch!(@notice, key)

  defstruct [
    :notify_type,
    :channel_name
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{notify_type: notify_type, channel_name: channel_name}) do
    <<notify_type::little-size(8)>> <> channel_name <> <<0>>
  end
end
