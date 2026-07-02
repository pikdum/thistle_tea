defmodule ThistleTea.Game.Network.Message.SmsgMessagechat do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MESSAGECHAT

  @chat_type_say 0x0
  @chat_type_party 0x1
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_system 0x0A
  @chat_type_monster_say 0x0B
  @chat_type_monster_yell 0x0C
  @chat_type_monster_emote 0x0D
  @chat_type_channel 0x0E

  @chat_type %{
    say: @chat_type_say,
    party: @chat_type_party,
    yell: @chat_type_yell,
    whisper: @chat_type_whisper,
    channel: @chat_type_channel,
    monster_say: @chat_type_monster_say,
    monster_yell: @chat_type_monster_yell,
    monster_emote: @chat_type_monster_emote
  }

  def chat_type, do: @chat_type
  def chat_type(key), do: Map.fetch!(@chat_type, key)

  defstruct [
    :chat_type,
    :language,
    :sender_guid,
    :sender_name,
    :target_guid,
    :message,
    :channel_name,
    :player_rank,
    :tag
  ]

  def system(message, sender_guid) do
    %__MODULE__{
      chat_type: @chat_type_system,
      language: 0,
      sender_guid: sender_guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
  end

  def monster(chat_type, message, sender_guid, sender_name, target_guid)
      when is_atom(chat_type) and is_binary(message) do
    %__MODULE__{
      chat_type: chat_type(chat_type),
      language: 0,
      sender_guid: sender_guid,
      sender_name: sender_name || "",
      target_guid: target_guid || 0,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
  end

  @impl ServerMessage
  def to_binary(
        %__MODULE__{
          chat_type: chat_type,
          language: _language,
          sender_guid: sender_guid,
          message: message,
          channel_name: channel_name,
          player_rank: player_rank,
          tag: tag
        } = msg
      ) do
    message_length = String.length(message) + 1
    # TODO: hardcoded language to 0 (universal) for now
    language = 0

    <<chat_type::little-size(8), language::little-size(32)>> <>
      sender_block(chat_type, msg, sender_guid, channel_name, player_rank) <>
      <<message_length::little-size(32)>> <>
      message <>
      <<0, tag::little-size(8)>>
  end

  defp sender_block(chat_type, _msg, sender_guid, _channel_name, _player_rank)
       when chat_type in [@chat_type_say, @chat_type_party, @chat_type_yell] do
    <<sender_guid::little-size(64), sender_guid::little-size(64)>>
  end

  defp sender_block(chat_type, msg, sender_guid, _channel_name, _player_rank)
       when chat_type in [@chat_type_monster_say, @chat_type_monster_yell] do
    sender_name = msg.sender_name || ""
    target_guid = msg.target_guid || 0

    <<sender_guid::little-size(64), byte_size(sender_name) + 1::little-size(32)>> <>
      sender_name <> <<0, target_guid::little-size(64)>>
  end

  defp sender_block(@chat_type_monster_emote, msg, _sender_guid, _channel_name, _player_rank) do
    sender_name = msg.sender_name || ""
    target_guid = msg.target_guid || 0

    <<byte_size(sender_name) + 1::little-size(32)>> <>
      sender_name <> <<0, target_guid::little-size(64)>>
  end

  defp sender_block(@chat_type_channel, _msg, sender_guid, channel_name, player_rank) do
    channel_name <> <<0, player_rank::little-size(32), sender_guid::little-size(64)>>
  end

  defp sender_block(_chat_type, _msg, sender_guid, _channel_name, _player_rank) do
    <<sender_guid::little-size(64)>>
  end
end
