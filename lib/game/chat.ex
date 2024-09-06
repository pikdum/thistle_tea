defmodule ThistleTea.Game.Chat do
  import ThistleTea.Util, only: [parse_string: 1, send_packet: 2]

  require Logger

  @cmsg_messagechat 0x095
  @smsg_messagechat 0x096

  @cmsg_join_channel 0x097
  @cmsg_leave_channel 0x098

  @smsg_channel_notify 0x099
  # @smsg_channel_list 0x09B
  @smsg_chat_player_not_found 0x2A9

  @chat_type_say 0x0
  @chat_type_party 0x1
  # @chat_type_raid 0x2
  # @chat_type_guild 0x3
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_emote 0x8
  @chat_type_channel 0x0E

  @say_range 25
  @yell_range 300
  @emote_range 25

  defp messagechat_packet(
         chat_type,
         language,
         message,
         sender_guid,
         target_name
       ) do
    message_length = String.length(message) + 1

    <<chat_type::little-size(8), language::little-size(32)>> <>
      case chat_type do
        type when type in [@chat_type_say, @chat_type_party, @chat_type_yell] ->
          <<sender_guid::little-size(64), sender_guid::little-size(64)>>

        @chat_type_channel ->
          target_name <>
            <<
              0,
              # player rank
              0::little-size(32),
              sender_guid::little-size(64)
            >>

        _ ->
          <<sender_guid::little-size(64)>>
      end <>
      <<message_length::little-size(32)>> <>
      message <>
      <<
        0,
        # player chat tag
        0
      >>

    # SizedCString = size + string + null byte
    # message + names
  end

  def handle_chat(state, chat_type, language, message, _target_name)
      when chat_type in [@chat_type_say, @chat_type_yell, @chat_type_emote] do
    packet = messagechat_packet(chat_type, language, message, state.guid, nil)

    range =
      case chat_type do
        @chat_type_say -> @say_range
        @chat_type_yell -> @yell_range
        @chat_type_emote -> @emote_range
      end

    %{x: x, y: y, z: z} = state.character.movement
    nearby_players = SpatialHash.query(:players, state.character.map, x, y, z, range)

    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, @smsg_messagechat, packet})
    end
  end

  # TODO: prevent whispering self
  def handle_chat(state, @chat_type_whisper, language, message, target_name) do
    # TODO: should extract to functions
    with [[guid]] <- :ets.match(:guid_name, {:"$1", target_name, :_, :_, :_, :_}),
         pid <- :ets.lookup_element(:entities, guid, 2, nil) do
      packet =
        messagechat_packet(@chat_type_whisper, language, message, state.guid, target_name)

      GenServer.cast(pid, {:send_packet, @smsg_messagechat, packet})
    else
      _ ->
        packet = target_name <> <<0>>
        send_packet(@smsg_chat_player_not_found, packet)
    end
  end

  def handle_chat(
        state,
        @chat_type_channel,
        language,
        message,
        target_name
      ) do
    packet = messagechat_packet(@chat_type_channel, language, message, state.guid, target_name)

    ThistleTea.ChatChannel
    |> Registry.dispatch(target_name, fn entries ->
      for {pid, _} <- entries do
        GenServer.cast(pid, {:send_packet, @smsg_messagechat, packet})
      end
    end)
  end

  def handle_chat(
        state,
        chat_type,
        language,
        message,
        target_name
      ) do
    Logger.error("Unhandled chat type: #{chat_type}")
    packet = messagechat_packet(chat_type, language, message, state.guid, target_name)

    all_players =
      :ets.tab2list(:players)
      |> Enum.map(fn {_, guid} -> :ets.lookup_element(:entities, guid, 2) end)

    for pid <- all_players do
      GenServer.cast(pid, {:send_packet, @smsg_messagechat, packet})
    end
  end

  def handle_packet(@cmsg_messagechat, body, state) do
    <<chat_type::little-size(32), _language::little-size(32), rest::binary>> = body
    # hardcoded to universal language for now
    language = 0

    {target_name, rest} =
      if chat_type in [@chat_type_whisper, @chat_type_channel] do
        {:ok, target_name, rest} = parse_string(rest)
        {target_name, rest}
      else
        {nil, rest}
      end

    {:ok, message, _rest} = parse_string(rest)

    handle_chat(state, chat_type, language, message, target_name)
    {:continue, state}
  end

  def handle_packet(@cmsg_join_channel, body, state) do
    {:ok, channel_name, rest} = parse_string(body)
    {:ok, _channel_password, _} = parse_string(rest)
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    # TODO: is there an easier way to do this with registries?
    # to prevent duplicate channel joins
    with [] <- ThistleTea.ChatChannel |> Registry.values(channel_name, self()) do
      ThistleTea.ChatChannel
      |> Registry.register(channel_name, state.guid)

      notify_packet =
        <<
          # YOU_JOINED_NOTICE
          0x02::little-size(8)
        >> <> channel_name <> <<0>>

      send_packet(@smsg_channel_notify, notify_packet)
    end

    {:continue, state}
  end

  def handle_packet(@cmsg_leave_channel, body, state) do
    {:ok, channel_name, _} = parse_string(body)
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ThistleTea.ChatChannel
    |> Registry.unregister(channel_name)

    notify_packet =
      <<
        # YOU_LEFT_NOTICE
        0x03::little-size(8)
      >> <> channel_name <> <<0>>

    send_packet(@smsg_channel_notify, notify_packet)
    {:continue, state}
  end
end
