defmodule ThistleTea.Game.Network.Message.CmsgMessagechat do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MESSAGECHAT

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
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
  @speed_base 7.0
  @speed_min 0.1
  @speed_max 10.0

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
      ".go xyz <x> <y> <z> [map] - teleport",
      ".guid - show target guid",
      ".help - show help",
      ".modify speed <rate> - modify player speed from 0.1 to 10",
      ".move - move target to you",
      ".pid - show target pid",
      ".pos - show current position",
      ".speed <rate> - modify player speed from 0.1 to 10"
    ]

    system_message(state, "Commands:")

    commands
    |> Enum.sort()
    |> Enum.reduce(state, fn command, acc ->
      system_message(acc, command)
    end)
  end

  def handle_chat(state, a, b, ".speed" <> rest, c) do
    handle_chat(state, a, b, ".modify speed" <> rest, c)
  end

  def handle_chat(state, _, _, ".modify" <> params, _) do
    case params |> String.split(" ", trim: true) do
      ["speed", rate] ->
        handle_modify_speed(state, rate)

      _ ->
        Logger.error("Unhandled .modify call: #{params}")

        state
        |> system_message("Invalid command. Use: .modify <type> <n>")
    end
  end

  def handle_chat(state, _, _, ".pos" <> _, _) do
    {x, y, z, _o} = state.character.movement_block.position
    map = state.character.internal.map

    state
    |> system_message("#{x} #{y} #{z} #{map}")
  end

  def handle_chat(state, _, _, ".guid" <> _, _) do
    state
    |> system_message("Target GUID: #{state.target}")
  end

  def handle_chat(state, _, _, ".pid" <> _, _) do
    case Entity.pid(state.target) do
      pid when is_pid(pid) ->
        state
        |> system_message("Target PID: #{inspect(pid)}")

      _ ->
        state
        |> system_message("No PID found.")
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

    case state.character.movement_block.position do
      {x, y, z, _o} ->
        Entity.move_to(target, {x, y, z})
        state

      _ ->
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
      |> Enum.map(fn {_, guid} -> guid end)

    for guid <- all_players do
      Network.send_packet(message, guid)
    end

    state
  end

  defp handle_modify_speed(state, rate) do
    case Float.parse(rate) do
      {rate, _} when rate >= @speed_min and rate <= @speed_max ->
        {target, guid} = resolve_speed_target(state)
        speed = rate * @speed_base

        %Message.SmsgForceRunSpeedChange{guid: guid, speed: speed}
        |> Network.send_packet(target)

        state
        |> system_message("Speed set to #{rate}")

      _ ->
        state
        |> system_message("Invalid speed. Use: .modify speed <rate 0.1 - 10.0>")
    end
  end

  defp resolve_speed_target(state) do
    target_guid = Map.get(state, :target)

    cond do
      not is_integer(target_guid) ->
        {self(), state.guid}

      target_guid == state.guid ->
        {self(), state.guid}

      true ->
        if Guid.entity_type(target_guid) == :player and Entity.online?(target_guid) do
          {target_guid, target_guid}
        else
          {self(), state.guid}
        end
    end
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
