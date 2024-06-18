defmodule ThistleTea.Game.Chat do
  import ThistleTea.Util, only: [parse_string: 1, send_update_packet: 1]
  import ThistleTea.Game.UpdateObject, only: [generate_packet: 4]

  require Logger

  @cmsg_messagechat 0x095
  @smsg_messagechat 0x096

  @cmsg_join_channel 0x097

  @chat_type_say 0
  @chat_type_yell 5
  @chat_type_whisper 6
  @chat_type_emote 8
  @chat_type_channel 14

  @update_type_create_object2 3
  @object_type_unit 3
  @update_flag_living 0x20

  # TODO: could pattern match on chat type
  def handle_packet(@cmsg_messagechat, body, state) do
    <<chat_type::little-size(32), _language::little-size(32), rest::binary>> = body
    Logger.info("CMSG_MESSAGECHAT")

    {target_player, rest} =
      case chat_type do
        @chat_type_whisper ->
          {:ok, target_player, rest} = parse_string(rest)
          {target_player, rest}

        _ ->
          {nil, rest}
      end

    {channel, rest} =
      case chat_type do
        @chat_type_channel ->
          {:ok, channel, rest} = parse_string(rest)
          {channel, rest}

        _ ->
          {nil, rest}
      end

    # SizedCString = size + string + null byte
    {:ok, message, _rest} = parse_string(rest)
    message_length = String.length(message) + 1

    # hardcoded to universal language for now
    language = 0

    case chat_type do
      @chat_type_say ->
        packet =
          <<chat_type::little-size(8), language::little-size(32), state.guid::little-size(64),
            state.guid::little-size(64)>> <>
            <<message_length::little-size(32)>> <>
            message <>
            <<
              0,
              # player chat tag - hard code to 0 for now
              0
            >>

        fields = %{
          object_guid: :rand.uniform(10000) + 100,
          # unit + object
          object_type: 9,
          object_scale_x: :rand.uniform(5) + 0.0,
          unit_health: 100,
          unit_power_1: 100,
          unit_power_2: 100,
          unit_power_3: 100,
          unit_power_4: 100,
          unit_power_5: 100,
          unit_max_health: 100,
          unit_max_power_1: 100,
          unit_max_power_2: 100,
          unit_max_power_3: 100,
          unit_max_power_4: 100,
          unit_max_power_5: 100,
          unit_level: 5,
          # need to find mapping for these - factionalliance/factionhorde?
          unit_faction_template: 189,
          # boar
          unit_display_id: 503,
          unit_native_display_id: 503
        }

        mb = Map.put(state.character.movement, :update_flag, @update_flag_living)

        boarpacket = generate_packet(@update_type_create_object2, @object_type_unit, fields, mb)
        send_update_packet(boarpacket)

        # TODO: for now, everybody receives
        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            send(pid, {:send_packet, @smsg_messagechat, packet})
          end
        end)

      @chat_type_yell ->
        packet =
          <<chat_type::little-size(8), language::little-size(32), state.guid::little-size(64),
            state.guid::little-size(64)>> <>
            <<message_length::little-size(32)>> <>
            message <>
            <<
              0,
              # player chat tag - hard code to 0 for now
              0
            >>

        # TODO: for now, everybody receives
        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            send(pid, {:send_packet, @smsg_messagechat, packet})
          end
        end)

      @chat_type_whisper ->
        Logger.error("UNIMPLEMENTED: CMSG_MESSAGECHAT: WHISPER: #{target_player} -> #{message}")

      @chat_type_emote ->
        packet =
          <<chat_type::little-size(8), language::little-size(32), state.guid::little-size(64)>> <>
            <<message_length::little-size(32)>> <>
            message <>
            <<
              0,
              # player chat tag - hard code to 0 for now
              0
            >>

        # TODO: for now, everybody receives
        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            send(pid, {:send_packet, @smsg_messagechat, packet})
          end
        end)

      @chat_type_channel ->
        packet =
          <<chat_type::little-size(8), language::little-size(32)>> <>
            channel <>
            <<
              0,
              # player rank
              0::little-size(32),
              # player guid
              state.guid::little-size(64)
            >> <>
            <<message_length::little-size(32)>> <>
            message <>
            <<
              0,
              # player chat tag - hard code to 0 for now
              0
            >>

        # TODO: untested
        # TODO: for now, everybody receives
        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            send(pid, {:send_packet, @smsg_messagechat, packet})
          end
        end)

      unknown ->
        Logger.error("UNIMPLEMENTED: CMSG_MESSAGECHAT: UNKNOWN: #{inspect(unknown)}")
    end

    {:continue, state}
  end

  def handle_packet(@cmsg_join_channel, body, state) do
    # TODO: implement this
    {:ok, channel_name, rest} = parse_string(body)
    {:ok, _channel_password, _} = parse_string(rest)
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    {:continue, state}
  end
end
