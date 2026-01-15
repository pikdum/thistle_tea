defmodule ThistleTea.Game.Network.Message.CmsgMessagechat do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MESSAGECHAT

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

  def system_message(state, message) do
    Network.send_packet(%Message.SmsgMessagechat{
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
    {x, y, z, _o} = state.character.movement_block.position
    map = state.character.internal.map

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
      {:ok, x, y, z} -> teleport_player(state, x, y, z, state.character.internal.map)
      :error -> system_message(state, "Invalid command. Use: .go xyz <x> <y> <z> [map]")
    end
  end

  def handle_chat(state, _, _, ".move" <> _, _) do
    target = Map.get(state, :target)
    pid = :ets.lookup_element(:entities, target, 2, nil)

    case state.character.movement_block.position do
      {x, y, z, _o} ->
        GenServer.cast(pid, {:move_to, x, y, z})
        state

      nil ->
        state
    end
  end

  def handle_chat(state, chat_type, language, message, _target_name)
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

  def handle_chat(state, @chat_type_whisper, language, message, target_name) do
    case Metadata.find_guid_by(:name, target_name) do
      guid when is_integer(guid) ->
        pid = :ets.lookup_element(:entities, guid, 2, nil)

        %Message.SmsgMessagechat{
          chat_type: @chat_type_whisper,
          language: language,
          sender_guid: state.guid,
          message: message,
          channel_name: nil,
          player_rank: 0,
          tag: 0
        }
        |> Network.send_packet(pid)

      _ ->
        %Message.SmsgChatPlayerNotFound{name: target_name}
        |> Network.send_packet()
    end

    state
  end

  def handle_chat(state, @chat_type_channel, language, message, target_name) do
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

  def handle_chat(state, chat_type, language, message, target_name) do
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
      |> Enum.map(fn {_, guid} -> :ets.lookup_element(:entities, guid, 2) end)

    for pid <- all_players do
      Network.send_packet(message, pid)
    end

    state
  end

  @impl ClientMessage
  def handle(%__MODULE__{chat_type: chat_type, language: language, message: message, target_name: target_name}, state) do
    handle_chat(state, chat_type, language, message, target_name)
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
end
