defmodule ThistleTea.Game.Chat do
  @moduledoc """
  Routes incoming chat by audience while leaving membership and authorization
  to the owning world system.
  """
  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.ChatChannels
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  require Logger

  @say 0x00
  @party 0x01
  @raid 0x02
  @guild 0x03
  @officer 0x04
  @yell 0x05
  @whisper 0x06
  @emote 0x08
  @channel 0x0E

  @say_range 25
  @yell_range 300
  @emote_range 25

  def handle(state, chat_type, language, message, target_name) do
    case DevCommands.run(state, message) do
      {:handled, state} -> state
      :unhandled -> route(state, chat_type, language, message, target_name)
    end
  end

  def actor(%{guid: guid, character: character}) do
    %Member{
      guid: guid,
      name: character.internal.name,
      team: team_for_race(character.unit.race)
    }
  end

  defp route(state, chat_type, language, message, _target_name) when chat_type in [@say, @yell, @emote] do
    packet = chat_packet(chat_type, language, state.guid, message)
    World.broadcast_packet(packet, state.character, range: range(chat_type))
    state
  end

  defp route(state, @whisper, language, message, target_name) do
    case Metadata.find_guid_by(:name, target_name) do
      guid when is_integer(guid) ->
        packet = chat_packet(@whisper, language, state.guid, message)

        case Network.send_packet(packet, guid) do
          :ok -> :ok
          _ -> Network.send_packet(%Message.SmsgChatPlayerNotFound{name: target_name})
        end

      _ ->
        Network.send_packet(%Message.SmsgChatPlayerNotFound{name: target_name})
    end

    state
  end

  defp route(state, @channel, language, message, channel_name) do
    ChatChannels.say(actor(state), channel_name, language, message)
    state
  end

  defp route(state, @party, language, message, _target_name) do
    case PartySystem.group_of(state.guid) do
      %Group{} = group -> PartyNotifier.broadcast(group, chat_packet(@party, language, state.guid, message))
      _ -> :ok
    end

    state
  end

  defp route(state, chat_type, _language, _message, _target_name) when chat_type in [@raid, @guild, @officer] do
    Logger.warning("Unsupported chat audience: #{chat_type}")
    state
  end

  defp route(state, chat_type, _language, _message, _target_name) do
    Logger.warning("Unknown chat type: #{chat_type}")
    state
  end

  defp chat_packet(chat_type, language, sender_guid, message) do
    %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: sender_guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: 0
    }
  end

  defp range(@say), do: @say_range
  defp range(@yell), do: @yell_range
  defp range(@emote), do: @emote_range

  defp team_for_race(race) when race in [1, 3, 4, 7], do: :alliance
  defp team_for_race(race) when race in [2, 5, 6, 8], do: :horde
  defp team_for_race(_race), do: :neutral
end
