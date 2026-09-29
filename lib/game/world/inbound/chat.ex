defmodule ThistleTea.Game.World.Inbound.Chat do
  @moduledoc "Handles decoded chat, channel, and emote client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Chat
  alias ThistleTea.Game.World.Entity.Player.Emotes
  alias ThistleTea.Game.World.System.ChatChannels

  require Logger

  def messages do
    [
      Message.CmsgChannelAnnouncements,
      Message.CmsgChannelBan,
      Message.CmsgChannelInvite,
      Message.CmsgChannelKick,
      Message.CmsgChannelList,
      Message.CmsgChannelModerate,
      Message.CmsgChannelModerator,
      Message.CmsgChannelMute,
      Message.CmsgChannelOwner,
      Message.CmsgChannelPassword,
      Message.CmsgChannelSetOwner,
      Message.CmsgChannelUnban,
      Message.CmsgChannelUnmoderator,
      Message.CmsgChannelUnmute,
      Message.CmsgEmote,
      Message.CmsgJoinChannel,
      Message.CmsgLeaveChannel,
      Message.CmsgMessagechat,
      Message.CmsgTextEmote
    ]
  end

  def handle(%Message.CmsgChannelAnnouncements{channel_name: name}, state) do
    ChatChannels.announcements(Chat.actor(state), name)
    state
  end

  def handle(%Message.CmsgChannelBan{channel_name: name, player_name: player_name}, state) do
    ChatChannels.ban(Chat.actor(state), name, player_name)
    state
  end

  def handle(%Message.CmsgChannelInvite{channel_name: name, player_name: player_name}, state) do
    ChatChannels.invite(Chat.actor(state), name, player_name)
    state
  end

  def handle(%Message.CmsgChannelKick{channel_name: name, player_name: player_name}, state) do
    ChatChannels.kick(Chat.actor(state), name, player_name)
    state
  end

  def handle(%Message.CmsgChannelList{channel_name: name}, state) do
    ChatChannels.list(Chat.actor(state), name)
    state
  end

  def handle(%Message.CmsgChannelModerate{channel_name: name}, state) do
    ChatChannels.moderate(Chat.actor(state), name)
    state
  end

  def handle(%Message.CmsgChannelModerator{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_moderator(Chat.actor(state), name, player_name, true)
    state
  end

  def handle(%Message.CmsgChannelMute{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_muted(Chat.actor(state), name, player_name, true)
    state
  end

  def handle(%Message.CmsgChannelOwner{channel_name: name}, state) do
    ChatChannels.owner(Chat.actor(state), name)
    state
  end

  def handle(%Message.CmsgChannelPassword{channel_name: name, password: password}, state) do
    ChatChannels.password(Chat.actor(state), name, password)
    state
  end

  def handle(%Message.CmsgChannelSetOwner{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_owner(Chat.actor(state), name, player_name)
    state
  end

  def handle(%Message.CmsgChannelUnban{channel_name: name, player_name: player_name}, state) do
    ChatChannels.unban(Chat.actor(state), name, player_name)
    state
  end

  def handle(%Message.CmsgChannelUnmoderator{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_moderator(Chat.actor(state), name, player_name, false)
    state
  end

  def handle(%Message.CmsgChannelUnmute{channel_name: name, player_name: player_name}, state) do
    ChatChannels.set_muted(Chat.actor(state), name, player_name, false)
    state
  end

  def handle(%Message.CmsgEmote{emote: emote}, state), do: Emotes.command(state, emote)

  def handle(%Message.CmsgJoinChannel{channel_name: channel_name, password: password}, state) do
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    ChatChannels.join(Chat.actor(state), channel_name, password)

    state
  end

  def handle(%Message.CmsgLeaveChannel{channel_name: channel_name}, state) do
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ChatChannels.leave(Chat.actor(state), channel_name)

    state
  end

  def handle(
        %Message.CmsgMessagechat{chat_type: chat_type, language: language, message: message, target_name: target_name},
        state
      ) do
    Chat.handle(state, chat_type, language, message, target_name)
  end

  def handle(%Message.CmsgTextEmote{text_emote: text_emote, emote: emote, target: target}, state) do
    Emotes.text(state, text_emote, emote, target)
  end
end
