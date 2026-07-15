defmodule ThistleTea.Game.World.System.ChatChannels do
  @moduledoc """
  Boundary for chat channels: serializes mutations through the pure channel
  core and interprets outcomes as network messages.
  """
  use GenServer

  alias ThistleTea.Game.Chat.Channel
  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Chat.Channels
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.ChatChannel, as: ChatChannelLoader
  alias ThistleTea.Game.World.Metadata

  require Logger

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def join(%Member{} = actor, name, password), do: call({:join, actor, name, password})
  def leave(%Member{} = actor, name), do: call({:leave, actor, name})
  def leave_all(guid) when is_integer(guid), do: call({:leave_all, guid})
  def say(%Member{} = actor, name, language, message), do: call({:say, actor, name, language, message})
  def list(%Member{} = actor, name), do: call({:list, actor, name})
  def password(%Member{} = actor, name, password), do: call({:password, actor, name, password})
  def set_owner(%Member{} = actor, name, target), do: call({:set_owner, actor, name, target})

  def set_moderator(%Member{} = actor, name, target, enabled?),
    do: call({:mode, actor, name, target, :moderator, enabled?})

  def set_muted(%Member{} = actor, name, target, enabled?), do: call({:mode, actor, name, target, :muted, enabled?})
  def kick(%Member{} = actor, name, target), do: call({:kick, actor, name, target, false})
  def ban(%Member{} = actor, name, target), do: call({:kick, actor, name, target, true})
  def unban(%Member{} = actor, name, target), do: call({:unban, actor, name, target})
  def invite(%Member{} = actor, name, target), do: call({:invite, actor, name, target})
  def announcements(%Member{} = actor, name), do: call({:announcements, actor, name})
  def moderate(%Member{} = actor, name), do: call({:moderate, actor, name})
  def owner(%Member{} = actor, name), do: call({:owner, actor, name})

  @impl GenServer
  def init(opts) do
    definitions =
      if Keyword.get(opts, :load_catalog, true), do: ChatChannelLoader.load(), else: ChatChannelLoader.defaults()

    {:ok, %{channels: %Channels{}, definitions: definitions}}
  end

  @impl GenServer
  def handle_call(request, from, state) do
    dispatch_call(request, from, state)
  rescue
    error ->
      Logger.error(Exception.format(:error, error, __STACKTRACE__))
      {:reply, {:error, :internal_error}, state}
  end

  defp dispatch_call({:join, actor, name, password}, _from, state) do
    if valid_name?(name) do
      definition = ChatChannelLoader.resolve(state.definitions, name)
      join_channel(state, actor, name, password, definition)
    else
      send_error(actor.guid, name, :invalid_name)
      {:reply, {:error, :invalid_name}, state}
    end
  end

  defp dispatch_call({:leave, actor, name}, _from, state) do
    case Channels.leave(state.channels, actor, name) do
      {:ok, channel, outcome, channels} ->
        notify_leave(channel, actor.guid, outcome, true)
        {:reply, :ok, %{state | channels: channels}}

      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:leave_all, guid}, _from, state) do
    {outcomes, channels} = Channels.leave_all(state.channels, guid)
    Enum.each(outcomes, fn {channel, outcome} -> notify_leave(channel, guid, outcome, false) end)
    {:reply, :ok, %{state | channels: channels}}
  end

  defp dispatch_call({:say, actor, name, language, message}, _from, state) do
    with {:ok, channel} <- Channels.fetch(state.channels, actor, name),
         {:ok, members} <- Channel.speak(channel, actor.guid) do
      packet = %Message.SmsgMessagechat{
        chat_type: Message.SmsgMessagechat.chat_type(:channel),
        language: language,
        sender_guid: actor.guid,
        message: message,
        channel_name: channel.name,
        player_rank: 0,
        tag: 0
      }

      send_to_members(members, packet)
      {:reply, :ok, state}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:list, actor, name}, _from, state) do
    with {:ok, channel} <- Channels.fetch(state.channels, actor, name),
         {:ok, members} <- Channel.list(channel, actor.guid) do
      Network.send_packet(
        %Message.SmsgChannelList{channel_name: channel.name, channel_flags: channel.flags, members: members},
        actor.guid
      )

      {:reply, :ok, state}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:password, actor, name, password}, _from, state) do
    mutate(state, actor, name, &change_password(&1, actor, password))
  end

  defp dispatch_call({:set_owner, actor, name, target}, _from, state) do
    mutate(state, actor, name, &change_owner(&1, actor, target))
  end

  defp dispatch_call({:mode, actor, name, target, mode, enabled?}, _from, state) do
    mutate(state, actor, name, &change_mode(&1, actor, target, mode, enabled?))
  end

  defp dispatch_call({:kick, actor, name, target, ban?}, _from, state) do
    with {:ok, current} <- Channels.fetch(state.channels, actor, name),
         {:ok, channel, outcome} <- Channel.kick(current, actor.guid, target, ban?) do
      packet_type = if ban?, do: :player_banned, else: :player_kicked

      packet =
        notice(channel, packet_type,
          target_guid: outcome.target.guid,
          source_guid: actor.guid
        )

      send_to_channel(current, packet)
      notify_owner_change(channel, outcome.owner_change)
      channels = Channels.remove_member(state.channels, channel, outcome.target.guid)
      {:reply, :ok, %{state | channels: channels}}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:unban, actor, name, target_name}, _from, state) do
    case find_player(target_name) do
      {:ok, target} ->
        mutate(state, actor, name, &remove_ban(&1, actor, target))

      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:invite, actor, name, target_name}, _from, state) do
    with {:ok, channel} <- Channels.fetch(state.channels, actor, name),
         {:ok, target} <- find_player(target_name),
         :ok <- Channel.invite(channel, actor.guid, target) do
      Network.send_packet(notice(channel, :invite, guid: actor.guid), target.guid)
      Network.send_packet(notice(channel, :player_invited, player_name: target.name), actor.guid)
      {:reply, :ok, state}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp dispatch_call({:announcements, actor, name}, _from, state) do
    mutate(state, actor, name, &change_announcements(&1, actor))
  end

  defp dispatch_call({:moderate, actor, name}, _from, state) do
    mutate(state, actor, name, &change_moderation(&1, actor))
  end

  defp dispatch_call({:owner, actor, name}, _from, state) do
    with {:ok, channel} <- Channels.fetch(state.channels, actor, name),
         {:ok, _member} <- Channel.fetch_member(channel, actor.guid) do
      owner_name = channel.members |> Map.get(channel.owner_guid, %Member{name: "Nobody"}) |> then(& &1.name)
      Network.send_packet(notice(channel, :channel_owner, owner_name: owner_name), actor.guid)
      {:reply, :ok, state}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp mutate(state, actor, name, operation) do
    with {:ok, current} <- Channels.fetch(state.channels, actor, name),
         {:ok, channel, after_commit} <- operation.(current) do
      after_commit.()
      {:reply, :ok, %{state | channels: Channels.put(state.channels, channel)}}
    else
      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp join_channel(state, actor, name, password, definition) do
    case Channels.join(state.channels, actor, name, password, definition) do
      {:ok, channel, outcome, channels} ->
        notify_join(channel, outcome)
        {:reply, :ok, %{state | channels: channels}}

      {:error, reason} ->
        send_error(actor.guid, name, reason)
        {:reply, {:error, reason}, state}
    end
  end

  defp change_password(channel, actor, password) do
    with {:ok, channel} <- Channel.set_password(channel, actor.guid, password) do
      packet = notice(channel, :password_changed, guid: actor.guid)
      {:ok, channel, fn -> send_to_channel(channel, packet) end}
    end
  end

  defp change_owner(channel, actor, target) do
    with {:ok, channel, outcome} <- Channel.set_owner(channel, actor.guid, target) do
      {:ok, channel, fn -> notify_set_owner(channel, outcome) end}
    end
  end

  defp change_mode(channel, actor, target, mode, enabled?) do
    with {:ok, channel, outcome} <- Channel.set_mode(channel, actor.guid, target, mode, enabled?) do
      packet = mode_notice(channel, outcome.member, outcome.old_flags)
      {:ok, channel, fn -> send_to_channel(channel, packet) end}
    end
  end

  defp remove_ban(channel, actor, target) do
    with {:ok, channel} <- Channel.unban(channel, actor.guid, target.guid, target.name) do
      packet = notice(channel, :player_unbanned, target_guid: target.guid, source_guid: actor.guid)
      {:ok, channel, fn -> send_to_channel(channel, packet) end}
    end
  end

  defp change_announcements(channel, actor) do
    with {:ok, channel} <- Channel.toggle_announcements(channel, actor.guid) do
      type = if channel.announcements?, do: :announcements_on, else: :announcements_off
      packet = notice(channel, type, guid: actor.guid)
      {:ok, channel, fn -> send_to_channel(channel, packet) end}
    end
  end

  defp change_moderation(channel, actor) do
    with {:ok, channel} <- Channel.toggle_moderation(channel, actor.guid) do
      type = if channel.moderated?, do: :moderation_on, else: :moderation_off
      packet = notice(channel, type, guid: actor.guid)
      {:ok, channel, fn -> send_to_channel(channel, packet) end}
    end
  end

  defp notify_join(channel, outcome) do
    if channel.announcements? do
      send_to_guids(outcome.recipients, notice(channel, :joined, guid: outcome.member.guid))
    end

    Network.send_packet(
      notice(channel, :you_joined, channel_flags: channel.flags, channel_index: 0),
      outcome.member.guid
    )

    if outcome.owner_assigned? do
      send_to_channel(channel, mode_notice(channel, outcome.member, 0))
    end
  end

  defp notify_leave(channel, guid, outcome, notify_self?) do
    if notify_self?, do: Network.send_packet(notice(channel, :you_left), guid)

    if channel.announcements? do
      send_to_guids(outcome.recipients, notice(channel, :left, guid: guid))
    end

    notify_owner_change(channel, outcome.owner_change)
  end

  defp notify_set_owner(channel, outcome) do
    if outcome.old_owner do
      old_owner = Map.get(channel.members, outcome.old_owner.guid, %{outcome.old_owner | flags: 0})
      send_to_channel(channel, mode_notice(channel, old_owner, outcome.old_owner.flags))
    end

    send_to_channel(channel, mode_notice(channel, outcome.new_owner, outcome.new_owner_old_flags))
    send_to_channel(channel, notice(channel, :owner_changed, guid: outcome.new_owner.guid))
  end

  defp notify_owner_change(_channel, nil), do: :ok

  defp notify_owner_change(channel, owner_change) do
    send_to_channel(channel, mode_notice(channel, owner_change.member, owner_change.old_flags))
    send_to_channel(channel, notice(channel, :owner_changed, guid: owner_change.member.guid))
  end

  defp mode_notice(channel, member, old_flags) do
    notice(channel, :mode_change, guid: member.guid, old_flags: old_flags, new_flags: member.flags)
  end

  defp send_error(guid, name, reason) do
    {type, attrs} = error_notice(reason, guid)
    channel = %Channel{name: name}
    Network.send_packet(notice(channel, type, attrs), guid)
  end

  defp error_notice(:already_member, guid), do: {:player_already_member, [guid: guid]}
  defp error_notice(:banned, _guid), do: {:banned, []}
  defp error_notice(:wrong_password, _guid), do: {:wrong_password, []}
  defp error_notice(:not_member, _guid), do: {:not_member, []}
  defp error_notice(:not_moderator, _guid), do: {:not_moderator, []}
  defp error_notice(:not_owner, _guid), do: {:not_owner, []}
  defp error_notice(:muted, _guid), do: {:muted, []}
  defp error_notice(:wrong_faction, _guid), do: {:invite_wrong_faction, []}
  defp error_notice(:invalid_name, _guid), do: {:invalid_name, []}
  defp error_notice({:player_not_found, name}, _guid), do: {:player_not_found, [player_name: name]}
  defp error_notice({:already_member, guid}, _actor_guid), do: {:player_already_member, [guid: guid]}
  defp error_notice({:invite_banned, name}, _guid), do: {:player_invite_banned, [player_name: name]}
  defp error_notice({:not_banned, name}, _guid), do: {:player_not_banned, [player_name: name]}

  defp notice(channel, type, attrs \\ []) do
    struct(
      Message.SmsgChannelNotify,
      [notify_type: Message.SmsgChannelNotify.notice(type), channel_name: channel.name] ++ attrs
    )
  end

  defp send_to_channel(channel, packet), do: send_to_members(Map.values(channel.members), packet)
  defp send_to_members(members, packet), do: members |> Enum.map(& &1.guid) |> send_to_guids(packet)
  defp send_to_guids(guids, packet), do: Enum.each(guids, &Network.send_packet(packet, &1))

  defp find_player(name) do
    case Metadata.find_guid_by(:name, name) do
      guid when is_integer(guid) ->
        case Metadata.query(guid, [:name, :race]) do
          %{name: player_name, race: race} -> {:ok, %Member{guid: guid, name: player_name, team: team_for_race(race)}}
          _ -> {:error, {:player_not_found, name}}
        end

      _ ->
        case CharacterStore.get_by_name(name) do
          %Character{} = character ->
            {:ok,
             %Member{
               guid: character.object.guid,
               name: character.internal.name,
               team: team_for_race(character.unit.race)
             }}

          _ ->
            {:error, {:player_not_found, name}}
        end
    end
  end

  defp team_for_race(race) when race in [1, 3, 4, 7], do: :alliance
  defp team_for_race(race) when race in [2, 5, 6, 8], do: :horde
  defp team_for_race(_race), do: :neutral

  defp valid_name?(name) when is_binary(name) and byte_size(name) <= 128 do
    Regex.match?(~r/^\p{L}/u, name)
  end

  defp valid_name?(_name), do: false

  defp call(message), do: GenServer.call(__MODULE__, message)
end
