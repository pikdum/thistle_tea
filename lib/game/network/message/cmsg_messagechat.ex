defmodule ThistleTea.Game.Network.Message.CmsgMessagechat do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MESSAGECHAT

  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.World.Metadata

  require Logger

  defstruct [:chat_type, :language, :message, :target_name]

  @chat_type_say 0x0
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_emote 0x8
  @chat_type_channel 0x0E

  @say_range 25
  @yell_range 300
  @emote_range 25

  @impl ClientMessage
  def handle(%__MODULE__{chat_type: chat_type, language: language, message: message, target_name: target_name}, state) do
    case DevCommands.run(state, message) do
      {:handled, state} -> state
      :unhandled -> handle_chat(state, chat_type, language, message, target_name)
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<chat_type::little-size(32), language::little-size(32), rest::binary>> = payload

    {target_name, rest} =
      if chat_type in [@chat_type_whisper, @chat_type_channel] do
        {:ok, target_name, rest} = BinaryUtils.parse_string(rest)
        {target_name, rest}
      else
        {nil, rest}
      end

    {:ok, message, _rest} = BinaryUtils.parse_string(rest)

    %__MODULE__{
      chat_type: chat_type,
      language: language,
      message: message,
      target_name: target_name
    }
  end

  defp handle_chat(state, chat_type, language, message, _target_name)
       when chat_type in [@chat_type_say, @chat_type_yell, @chat_type_emote] do
    range =
      case chat_type do
        @chat_type_say -> @say_range
        @chat_type_yell -> @yell_range
        @chat_type_emote -> @emote_range
      end

    %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
    |> World.broadcast_packet(state.character, range: range)

    state
  end

  defp handle_chat(state, @chat_type_whisper, language, message, target_name) do
    case Metadata.find_guid_by(:name, target_name) do
      guid when is_integer(guid) ->
        message = %Message.SmsgMessagechat{
          chat_type: @chat_type_whisper,
          language: language,
          sender_guid: state.guid,
          message: message,
          channel_name: nil,
          player_rank: 0,
          tag: 0
        }

        case Network.send_packet(message, guid) do
          :ok ->
            :ok

          _ ->
            %Message.SmsgChatPlayerNotFound{name: target_name}
            |> Network.send_packet()
        end

      _ ->
        %Message.SmsgChatPlayerNotFound{name: target_name}
        |> Network.send_packet()
    end

    state
  end

  defp handle_chat(state, @chat_type_channel, language, message, target_name) do
    message = %Message.SmsgMessagechat{
      chat_type: @chat_type_channel,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: target_name,
      player_rank: 0,
      tag: 0
    }

    ThistleTea.ChatChannel
    |> Registry.dispatch(target_name, fn entries ->
      for {pid, _} <- entries do
        Network.send_packet(message, pid)
      end
    end)

    state
  end

  defp handle_chat(state, chat_type, language, message, target_name) do
    Logger.error("Unhandled chat type: #{chat_type}")

    message = %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: state.guid,
      message: message,
      channel_name: target_name,
      player_rank: 0,
      tag: 0
    }

    all_players =
      :ets.tab2list(:players)
      |> Enum.map(fn {_, guid} -> guid end)

    for guid <- all_players do
      Network.send_packet(message, guid)
    end

    state
  end
end
