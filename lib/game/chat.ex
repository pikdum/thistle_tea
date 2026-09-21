defmodule ThistleTea.Game.Chat do
  @moduledoc """
  Routes incoming chat by audience while leaving membership and authorization
  to the owning world system.
  """
  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Entity.Data.ChatStatus
  alias ThistleTea.Game.Entity.Logic.ChatStatus, as: StatusLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.ChatStatus, as: PlayerStatus
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
  @afk 0x14
  @dnd 0x15
  @raid_leader 0x57
  @raid_warning 0x58

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
      chat_tag: StatusLogic.tag(character),
      team: team_for_race(character.unit.race)
    }
  end

  defp route(state, chat_type, language, message, _target_name) when chat_type in [@say, @yell, @emote] do
    language = if chat_type == @emote, do: 0, else: language
    packet = chat_packet(chat_type, language, state.guid, message, StatusLogic.tag(state.character))
    World.broadcast_packet(packet, state.character, range: range(chat_type))
    state
  end

  defp route(state, @whisper, language, message, target_name) do
    language = if language == 0xFFFFFFFF, do: language, else: 0

    case Metadata.find_guid_by(:name, String.capitalize(target_name)) do
      guid when is_integer(guid) ->
        packet = chat_packet(@whisper, language, state.guid, message, StatusLogic.tag(state.character))

        case Network.send_packet(packet, guid) do
          :ok -> whisper_reply(state.guid, guid, language, message)
          _ -> Network.send_packet(%Message.SmsgChatPlayerNotFound{name: target_name})
        end

      _ ->
        Network.send_packet(%Message.SmsgChatPlayerNotFound{name: target_name})
    end

    state
  end

  defp route(state, @afk, _language, message, _target), do: PlayerStatus.change(state, :afk, message)
  defp route(state, @dnd, _language, message, _target), do: PlayerStatus.change(state, :dnd, message)

  defp route(state, @channel, language, message, channel_name) do
    ChatChannels.say(actor(state), channel_name, language, message)
    state
  end

  defp route(state, @party, language, message, _target_name) do
    case PartySystem.group_of(state.guid) do
      %Group{} = group ->
        packet = chat_packet(@party, language, state.guid, message, StatusLogic.tag(state.character))
        member = Party.member(group, state.guid)
        PartyNotifier.broadcast(group, packet, subgroup: member.subgroup)

      _ ->
        :ok
    end

    state
  end

  defp route(state, chat_type, language, message, _target_name)
       when chat_type in [@raid, @raid_leader, @raid_warning] do
    with %Group{raid?: true} = group <- PartySystem.group_of(state.guid),
         true <- raid_chat_allowed?(group, state.guid, chat_type) do
      packet = chat_packet(chat_type, language, state.guid, message, StatusLogic.tag(state.character))
      PartyNotifier.broadcast(group, packet)
    end

    state
  end

  defp route(state, chat_type, _language, _message, _target_name) when chat_type in [@guild, @officer] do
    Logger.warning("Unsupported chat audience: #{chat_type}")
    state
  end

  defp route(state, chat_type, _language, _message, _target_name) do
    Logger.warning("Unknown chat type: #{chat_type}")
    state
  end

  defp whisper_reply(sender_guid, target_guid, language, message) do
    status =
      case Metadata.query(target_guid, [:chat_status]) do
        %{chat_status: %ChatStatus{} = status} -> status
        _ -> %ChatStatus{}
      end

    if language != 0xFFFFFFFF do
      Network.send_packet(chat_packet(0x07, 0, target_guid, message, StatusLogic.tag(status)), sender_guid)
    end

    case status do
      %ChatStatus{mode: mode, message: reply} when mode in [:afk, :dnd] ->
        type = if mode == :afk, do: @afk, else: @dnd
        Network.send_packet(chat_packet(type, 0, target_guid, reply, 0), sender_guid)

      _ ->
        :ok
    end
  end

  defp raid_chat_allowed?(_group, _guid, @raid), do: true
  defp raid_chat_allowed?(group, guid, @raid_leader), do: Party.leader?(group, guid)
  defp raid_chat_allowed?(group, guid, @raid_warning), do: Party.manager?(group, guid)

  defp chat_packet(chat_type, language, sender_guid, message, tag) do
    %Message.SmsgMessagechat{
      chat_type: chat_type,
      language: language,
      sender_guid: sender_guid,
      message: message,
      channel_name: nil,
      player_rank: 0,
      tag: tag
    }
  end

  defp range(@say), do: @say_range
  defp range(@yell), do: @yell_range
  defp range(@emote), do: @emote_range

  defp team_for_race(race) when race in [1, 3, 4, 7], do: :alliance
  defp team_for_race(race) when race in [2, 5, 6, 8], do: :horde
  defp team_for_race(_race), do: :neutral
end
