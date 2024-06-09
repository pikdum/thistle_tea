defmodule ThistleTea.Game.Chat do
  defmacro __using__(_) do
    quote do
      import ThistleTea.Util, only: [parse_string: 1]

      @cmsg_messagechat 0x095
      @smsg_messagechat 0x096

      @cmsg_join_channel 0x097

      @chat_type_say 0
      @chat_type_whisper 6
      @chat_type_channel 14

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_messagechat, _size, body}, {socket, state}) do
        <<chat_type::little-size(32), language::little-size(32), rest::binary>> = body
        Logger.info("[GameServer] CMSG_MESSAGECHAT: chat_type: #{inspect(chat_type)}")

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

            Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
              for {pid, _} <- entries do
                send(pid, {:send_packet, @smsg_messagechat, packet})
              end
            end)

          @chat_type_whisper ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: WHISPER: #{target_player} -> #{message}")

          @chat_type_channel ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: CHANNEL: #{channel} -> #{message}")

          _ ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: UNKNOWN: #{inspect(chat_type)}")
        end

        {:noreply, {socket, state}}
      end

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_join_channel, _size, body}, {socket, state}) do
        {:ok, channel_name, rest} = parse_string(body)
        {:ok, channel_password, _} = parse_string(rest)
        Logger.info("[GameServer] CMSG_JOIN_CHANNEL: #{channel_name} -> #{channel_password}")

        {:noreply, {socket, state}}
      end
    end
  end
end
