defmodule ThistleTea.Game.Chat do
  use ThistleTea.Opcodes, [
    :CMSG_MESSAGECHAT,
    :SMSG_MESSAGECHAT,
    :CMSG_JOIN_CHANNEL,
    :CMSG_LEAVE_CHANNEL,
    :CMSG_TEXT_EMOTE,
    :SMSG_CHANNEL_NOTIFY,
    :SMSG_CHAT_PLAYER_NOT_FOUND
  ]

  import ThistleTea.Util, only: [parse_string: 1]

  alias ThistleTea.Game.Chat.Emote
  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  @chat_type_say 0x0
  # @chat_type_party 0x1
  # @chat_type_raid 0x2
  # @chat_type_guild 0x3
  @chat_type_yell 0x5
  @chat_type_whisper 0x6
  @chat_type_emote 0x8
  @chat_type_channel 0x0E

  @say_range 25
  @yell_range 300
  @emote_range 25

  def system_message(state, message) do
    Util.send_packet(%Message.SmsgMessagechat{
      chat_type: 0x0A,
      language: 0,
      sender_guid: state.guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    })

    state
  end

  def teleport_player(state, x, y, z, map) do
    system_message(state, "Teleporting to #{x}, #{y}, #{z} on map #{map}")

    GenServer.cast(self(), {:start_teleport, x, y, z, map})

    state
  end

  defp parse_coords([x, y, z, map]) do
    with {x, _} <- Float.parse(x),
         {y, _} <- Float.parse(y),
         {z, _} <- Float.parse(z),
         {map, _} <- Integer.parse(map) do
      {:ok, x, y, z, map}
    else
      _ -> :error
    end
  end

  defp parse_coords([x, y, z]) do
    with {x, _} <- Float.parse(x),
         {y, _} <- Float.parse(y),
         {z, _} <- Float.parse(z) do
      {:ok, x, y, z}
    else
      _ -> :error
    end
  end

  def get_player_pids_in_chat_range(state, range) do
    {x, y, z, _o} = state.character.movement.position
    nearby_players = SpatialHash.query(:players, state.character.map, x, y, z, range)

    nearby_players |> Enum.map(fn {_, pid, _} -> pid end)
  end

  def handle_chat(state, _, _, ".help" <> _, _) do
    commands = [
      ".behavior - show mob behavior",
      ".go xyz <x> <y> <z> [map] - teleport",
      ".guid - show target guid",
      ".help - show help",
      ".move - move target to you",
      ".pid - show target pid",
      ".pos - show current position",
      ".interrupt_movement - interrupt mob movement"
    ]

    system_message(state, "Commands:")

    commands
    |> Enum.sort()
    |> Enum.reduce(state, fn command, acc ->
      system_message(acc, command)
    end)
  end

  def handle_chat(state, _, _, ".pos" <> _, _) do
    {x, y, z, _o} = state.character.movement.position
    map = state.character.map

    state
    |> system_message("#{x} #{y} #{z} #{map}")
  end

  def handle_chat(state, _, _, ".interrupt_movement" <> _, _) do
    # TODO: interrupting movement should probably fire movement_finished?
    # otherwise behavior never triggers movement again
    # or at least reset state
    case :ets.lookup_element(:entities, state.target, 2, nil) do
      pid when not is_nil(pid) ->
        GenServer.cast(pid, :interrupt_movement)

        state
        |> system_message("Interrupted movement.")

      nil ->
        state
        |> system_message("No mob found to interrupt.")
    end
  end

  def handle_chat(state, _, _, ".guid" <> _, _) do
    state
    |> system_message("Target GUID: #{state.target}")
  end

  def handle_chat(state, _, _, ".pid" <> _, _) do
    case :ets.lookup_element(:entities, state.target, 2, nil) do
      pid when not is_nil(pid) ->
        state
        |> system_message("Target PID: #{inspect(pid)}")

      nil ->
        state
        |> system_message("No PID found.")
    end
  end

  def handle_chat(state, _, _, ".behavior" <> _, _) do
    with pid when not is_nil(pid) <- :ets.lookup_element(:entities, state.target, 2, nil),
         :mob <- GenServer.call(pid, :get_entity),
         {:ok, behavior_state} <- GenServer.call(pid, :get_behavior) do
      behavior_state
      |> inspect(pretty: true)
      |> String.split("\n")
      |> Enum.each(fn line ->
        system_message(state, line)
      end)

      state
    else
      _ -> state |> system_message("No behavior found.")
    end
  end

  def handle_chat(state, _, _, ".go xyz " <> rest, _) do
    case rest |> String.split(" ", trim: true) |> parse_coords() do
      {:ok, x, y, z, map} -> teleport_player(state, x, y, z, map)
      {:ok, x, y, z} -> teleport_player(state, x, y, z, state.character.map)
      :error -> system_message(state, "Invalid command. Use: .go xyz <x> <y> <z> [map]")
    end
  end

  def handle_chat(state, _, _, ".move" <> _, _) do
    target = Map.get(state, :target)
    pid = :ets.lookup_element(:entities, target, 2, nil)

    case state.character.movement.position do
      {x, y, z, _o} ->
        GenServer.cast(pid, {:move_to, x, y, z})
        state

      nil ->
        state
    end
  end

  def handle_chat(state, chat_type, language, message, _target_name)
      when chat_type in [@chat_type_say, @chat_type_yell, @chat_type_emote] do
    packet =
      Message.to_packet(%Message.SmsgMessagechat{
        chat_type: chat_type,
        language: language,
        sender_guid: state.guid,
        message: message,
        channel_name: nil,
        player_rank: 0,
        tag: 0
      })

    range =
      case chat_type do
        @chat_type_say -> @say_range
        @chat_type_yell -> @yell_range
        @chat_type_emote -> @emote_range
      end

    pids_in_range = get_player_pids_in_chat_range(state, range)

    for pid <- pids_in_range do
      GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
    end

    state
  end

  def handle_chat(state, @chat_type_whisper, language, message, target_name) do
    case :ets.match(:guid_name, {:"$1", target_name, :_, :_, :_, :_}) do
      [[guid]] ->
        pid = :ets.lookup_element(:entities, guid, 2, nil)

        packet =
          Message.to_packet(%Message.SmsgMessagechat{
            chat_type: @chat_type_whisper,
            language: language,
            sender_guid: state.guid,
            message: message,
            channel_name: nil,
            player_rank: 0,
            tag: 0
          })

        GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})

      _ ->
        Util.send_packet(%Message.SmsgChatPlayerNotFound{name: target_name})
    end

    state
  end

  def handle_chat(state, @chat_type_channel, language, message, target_name) do
    packet =
      Message.to_packet(%Message.SmsgMessagechat{
        chat_type: @chat_type_channel,
        language: language,
        sender_guid: state.guid,
        message: message,
        channel_name: target_name,
        player_rank: 0,
        tag: 0
      })

    ThistleTea.ChatChannel
    |> Registry.dispatch(target_name, fn entries ->
      for {pid, _} <- entries do
        GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
      end
    end)

    state
  end

  def handle_chat(state, chat_type, language, message, target_name) do
    Logger.error("Unhandled chat type: #{chat_type}")

    packet =
      Message.to_packet(%Message.SmsgMessagechat{
        chat_type: chat_type,
        language: language,
        sender_guid: state.guid,
        message: message,
        channel_name: target_name,
        player_rank: 0,
        tag: 0
      })

    all_players =
      :ets.tab2list(:players)
      |> Enum.map(fn {_, guid} -> :ets.lookup_element(:entities, guid, 2) end)

    for pid <- all_players do
      GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
    end

    state
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

    state = handle_chat(state, chat_type, language, message, target_name)
    {:continue, state}
  end

  def handle_packet(@cmsg_join_channel, body, state) do
    {:ok, channel_name, rest} = parse_string(body)
    {:ok, _channel_password, _} = parse_string(rest)
    Logger.info("CMSG_JOIN_CHANNEL: #{channel_name}")

    with [] <- ThistleTea.ChatChannel |> Registry.values(channel_name, self()) do
      ThistleTea.ChatChannel
      |> Registry.register(channel_name, state.guid)

      Util.send_packet(%Message.SmsgChannelNotify{
        notify_type: 0x02,
        channel_name: channel_name
      })
    end

    {:continue, state}
  end

  def handle_packet(@cmsg_leave_channel, body, state) do
    {:ok, channel_name, _} = parse_string(body)
    Logger.info("CMSG_LEAVE_CHANNEL: #{channel_name}")

    ThistleTea.ChatChannel
    |> Registry.unregister(channel_name)

    Util.send_packet(%Message.SmsgChannelNotify{
      notify_type: 0x03,
      channel_name: channel_name
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_text_emote, body, state) do
    Emote.handle_packet(body, state)
    {:continue, state}
  end
end
