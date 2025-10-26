defmodule ThistleTea.Game.Message.SmsgMessagechat do
  use ThistleTea.Game.ServerMessage, :SMSG_MESSAGECHAT

  @chat_type_say 0x0
  @chat_type_party 0x1
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_channel 0x0E

  @chat_type %{
    say: @chat_type_say,
    party: @chat_type_party,
    yell: @chat_type_yell,
    whisper: @chat_type_whisper,
    channel: @chat_type_channel
  }

  def chat_type, do: @chat_type
  def chat_type(key), do: Map.fetch!(@chat_type, key)

  defstruct [
    :chat_type,
    :language,
    :sender_guid,
    :message,
    :channel_name,
    :player_rank,
    :tag
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        chat_type: chat_type,
        language: language,
        sender_guid: sender_guid,
        message: message,
        channel_name: channel_name,
        player_rank: player_rank,
        tag: tag
      }) do
    message_length = String.length(message) + 1

    <<chat_type::little-size(8), language::little-size(32)>> <>
      case chat_type do
        type when type in [@chat_type_say, @chat_type_party, @chat_type_yell] ->
          <<sender_guid::little-size(64), sender_guid::little-size(64)>>

        @chat_type_channel ->
          channel_name <>
            <<0, player_rank::little-size(32), sender_guid::little-size(64)>>

        _ ->
          <<sender_guid::little-size(64)>>
      end <>
      <<message_length::little-size(32)>> <>
      message <>
      <<0, tag::little-size(8)>>
  end
end
