defmodule ThistleTea.Game.Chat do
  defmacro __using__(_) do
    quote do
      import ThistleTea.Util, only: [parse_string: 1]

      @cmsg_messagechat 0x095
      @smsg_messagechat 0x096

      @chat_type_say 0
      @chat_type_whisper 6
      @chat_type_channel 14

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_messagechat, _size, body}, {socket, state}) do
        <<chat_type::little-size(32), language::little-size(32), rest::binary>> = body
        Logger.info("[GameServer] CMSG_MESSAGECHAT: #{inspect(language)}")

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

        {:ok, message, _rest} = parse_string(rest)

        case chat_type do
          @chat_type_say ->
            packet =
              <<chat_type::little-size(32), language::little-size(32),
                state.guid::little-size(64),
                state.guid::little-size(64)>> <>
                message <>
                <<
                  0,
                  # player chat tag - hard code to 0 for now
                  0
                >>

            Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
              for {pid, _} <- entries do
                Logger.info("[GameServer] CMSG_MESSAGECHAT: SAY: #{inspect(pid)}")
                send(pid, {:send_packet, @smsg_messagechat, packet})
              end
            end)

            Logger.info("[GameServer] CMSG_MESSAGECHAT: SAY: #{message}")

          @chat_type_whisper ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: WHISPER: #{target_player} -> #{message}")

          @chat_type_channel ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: CHANNEL: #{channel} -> #{message}")

          _ ->
            Logger.info("[GameServer] CMSG_MESSAGECHAT: UNKNOWN: #{inspect(chat_type)}")
        end

        {:noreply, {socket, state}}
      end
    end
  end
end
