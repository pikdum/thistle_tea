defmodule ThistleTea.Game.Player.Guilds do
  @moduledoc """
  Player-owner guild requests and client projections. The guild system owns
  membership; this boundary resolves names and publishes accepted changes.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.ChatStatus, as: StatusLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Group
  alias ThistleTea.Game.Guild.Member
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGuildCommandResult, as: CommandResult
  alias ThistleTea.Game.Network.Message.SmsgGuildRoster.Entry
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Game.World.System.Petition, as: PetitionSystem

  def create(%{ready: true, character: %Character{} = character} = state, name) do
    case GuildSystem.create(member(character), name) do
      {:ok, group} ->
        PetitionSystem.revoke_signer(character.object.guid)
        send_result(:create, name, :ok)
        state |> sync_membership() |> notify(group, :joined, [character.internal.name])

      {:error, reason} ->
        send_result(:create, name, reason)
        state
    end
  end

  def create(state, _name), do: state

  def invite(%{ready: true, guid: guid, character: %Character{} = character} = state, name) do
    target = CharacterStore.get_by_name(String.capitalize(name))

    result =
      cond do
        not match?(%Character{}, target) -> {:error, :player_not_found}
        not Entity.online?(target.object.guid) -> {:error, :player_not_found}
        SocialStore.ignores?(target.object.guid, guid) -> {:error, :permissions}
        true -> GuildSystem.invite(guid, member(target))
      end

    case result do
      {:ok, group} ->
        Network.send_packet(
          %Message.SmsgGuildInvite{inviter_name: character.internal.name, guild_name: group.name},
          target.object.guid
        )

        send_result(:invite, name, :ok)

      {:error, reason} ->
        send_result(:invite, name, reason)
    end

    state
  end

  def invite(state, _name), do: state

  def accept(%{ready: true, character: %Character{} = character} = state) do
    case GuildSystem.accept(member(character)) do
      {:ok, group} ->
        PetitionSystem.revoke_signer(character.object.guid)
        Network.send_packet(%Message.SmsgGuildEvent{event: :motd, descriptions: [group.motd]})
        state |> sync_membership() |> notify(group, :joined, [character.internal.name])

      {:error, reason} ->
        send_result(:invite, "", reason)
        state
    end
  end

  def accept(state), do: state

  def decline(%{ready: true, guid: guid} = state) do
    GuildSystem.decline(guid)
    state
  end

  def decline(state), do: state

  def query(state, guild_id) do
    case GuildSystem.group(guild_id) do
      %Group{} = group -> Network.send_packet(%Message.SmsgGuildQueryResponse{guild: group})
      nil -> send_result(:create, "", :not_in_guild)
    end

    state
  end

  def roster(%{ready: true, guid: guid} = state) do
    case GuildSystem.group_of(guid) do
      %Group{} = group -> send_roster(group, guid)
      nil -> send_result(:roster, "", :not_in_guild)
    end

    state
  end

  def roster(state), do: state

  def info(%{ready: true, guid: guid} = state) do
    case GuildSystem.group_of(guid) do
      %Group{} = group ->
        accounts =
          group.members
          |> Map.keys()
          |> Enum.map(&CharacterStore.get(Guid.low_guid(&1)))
          |> Enum.map(fn
            %Character{account_id: id} -> id
            _ -> nil
          end)
          |> Enum.uniq()
          |> length()

        Network.send_packet(%Message.SmsgGuildInfo{
          name: group.name,
          created_date: group.created_date,
          members: map_size(group.members),
          accounts: accounts
        })

      nil ->
        send_result(:create, "", :not_in_guild)
    end

    state
  end

  def info(state), do: state

  def promote(state, name), do: change_rank(state, name, :promote)
  def demote(state, name), do: change_rank(state, name, :demote)

  defp change_rank(%{ready: true, guid: guid} = state, name, action) do
    case named_member(guid, name) do
      %Member{guid: target_guid} ->
        perform_rank_change(state, guid, target_guid, name, action)

      nil ->
        send_result(:invite, name, :target_not_in_guild)
        state
    end
  end

  defp change_rank(state, _name, _action), do: state

  defp perform_rank_change(state, guid, target_guid, name, action) do
    case apply(GuildSystem, action, [guid, target_guid]) do
      {:ok, group} ->
        notify_member(target_guid)
        rank_name = group.ranks |> Enum.at(Guild.member(group, target_guid).rank) |> then(& &1.name)

        notify(state, group, if(action == :promote, do: :promotion, else: :demotion), [
          state.character.internal.name,
          name,
          rank_name
        ])

      {:error, reason} ->
        send_result(:invite, name, reason)
        state
    end
  end

  def remove(%{ready: true, guid: guid} = state, name) do
    case named_member(guid, name) do
      %Member{guid: target_guid} ->
        case GuildSystem.remove(guid, target_guid) do
          {:ok, group} ->
            notify_member(target_guid)
            notify(state, group, :removed, [name, state.character.internal.name])

          {:error, reason} ->
            send_result(:invite, name, reason)
            state
        end

      nil ->
        send_result(:invite, name, :target_not_in_guild)
        state
    end
  end

  def remove(state, _name), do: state

  def set_leader(%{ready: true, guid: guid} = state, name) do
    case named_member(guid, name) do
      %Member{guid: target_guid} ->
        case GuildSystem.set_leader(guid, target_guid) do
          {:ok, group} ->
            notify_member(target_guid)
            state |> sync_membership() |> notify(group, :leader_changed, [state.character.internal.name, name])

          {:error, reason} ->
            send_result(:founder, name, reason)
            state
        end

      nil ->
        send_result(:founder, name, :target_not_in_guild)
        state
    end
  end

  def set_leader(state, _name), do: state

  def set_motd(%{ready: true, guid: guid} = state, motd) when is_binary(motd) do
    case GuildSystem.set_motd(guid, motd) do
      {:ok, group} ->
        notify(state, group, :motd, [motd])

      {:error, reason} ->
        send_result(:roster, "", reason)
        state
    end
  end

  def set_motd(state, _motd), do: state

  def set_info(%{ready: true, guid: guid} = state, info) when is_binary(info) do
    case GuildSystem.set_info(guid, info) do
      {:ok, group} ->
        notify(state, group, :roster_update, [])

      {:error, reason} ->
        send_result(:roster, "", reason)
        state
    end
  end

  def set_info(state, _info), do: state

  def set_note(%{ready: true, guid: guid} = state, name, kind, note) do
    case named_member(guid, name) do
      %Member{guid: target_guid} ->
        case GuildSystem.set_note(guid, target_guid, kind, note) do
          {:ok, group} ->
            notify(state, group, :roster_update, [])

          {:error, reason} ->
            send_result(:roster, name, reason)
            state
        end

      nil ->
        send_result(:roster, name, :target_not_in_guild)
        state
    end
  end

  def set_note(state, _name, _kind, _note), do: state

  def edit_rank(%{ready: true, guid: guid} = state, rank_id, rights, name) do
    rank_result(state, GuildSystem.edit_rank(guid, rank_id, rights, name), false)
  end

  def edit_rank(state, _rank_id, _rights, _name), do: state

  def add_rank(%{ready: true, guid: guid} = state, name) do
    rank_result(state, GuildSystem.add_rank(guid, name), false)
  end

  def add_rank(state, _name), do: state

  def delete_rank(%{ready: true, guid: guid} = state) do
    rank_result(state, GuildSystem.delete_rank(guid), true)
  end

  def delete_rank(state), do: state

  defp rank_result(state, {:ok, group}, sync_members?) do
    if sync_members?, do: notify_rank_members(group, state.guid)

    Network.send_packet(%Message.SmsgGuildQueryResponse{guild: group})

    Enum.each(group.members, fn {guid, _member} ->
      if Entity.online?(guid), do: send_roster(group, guid)
    end)

    if sync_members?, do: sync_membership(state), else: state
  end

  defp rank_result(state, {:error, reason}, _sync_members?) do
    send_result(:roster, "", reason)
    state
  end

  defp notify_rank_members(group, actor_guid) do
    Enum.each(group.members, fn {guid, _member} ->
      if guid != actor_guid, do: notify_member(guid)
    end)
  end

  def leave(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    case GuildSystem.leave(guid) do
      {:ok, group} ->
        state = sync_membership(state)

        if map_size(group.members) == 1 do
          notify(state, group, :disbanded, [])
        else
          notify(state, group, :left, [character.internal.name])
        end

      {:error, reason} ->
        send_result(:quit, "", reason)
        state
    end
  end

  def leave(state), do: state

  def disband(%{ready: true, guid: guid} = state) do
    case GuildSystem.disband(guid) do
      {:ok, group} ->
        notify_disband_members(group, guid)
        state = sync_membership(state)
        notify(state, group, :disbanded, [])

      {:error, reason} ->
        send_result(:quit, "", reason)
        state
    end
  end

  def disband(state), do: state

  defp notify_disband_members(group, actor_guid) do
    Enum.each(group.members, fn {guid, _member} ->
      if guid != actor_guid, do: notify_member(guid)
    end)
  end

  def sync_membership(%{guid: guid, character: %Character{} = character} = state) do
    {guild_id, rank} = membership(guid)

    if character.player.guild_id == guild_id and character.player.guild_rank == rank do
      state
    else
      character = %{character | player: %{character.player | guild_id: guild_id, guild_rank: rank}}
      CharacterStore.put(character)

      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character)

      %{state | character: character}
    end
  end

  def sync_membership(state), do: state

  def attach(%Character{} = character) do
    {guild_id, rank} = membership(character.object.guid)
    %{character | player: %{character.player | guild_id: guild_id, guild_rank: rank}}
  end

  def charter_created(state, %Group{} = group) do
    Enum.each(group.members, fn {guid, _member} ->
      PetitionSystem.revoke_signer(guid)
      if guid != state.guid, do: notify_member(guid)
    end)

    state |> sync_membership() |> notify(group, :joined, [state.character.internal.name])
  end

  def signed_on(%Character{} = character) do
    case GuildSystem.group_of(character.object.guid) do
      %Group{} = group ->
        Network.send_packet(%Message.SmsgGuildEvent{event: :motd, descriptions: [group.motd]})
        notify_event(group, :signed_on, [character.internal.name])

      nil ->
        :ok
    end
  end

  def signed_off(%{guid: guid, character: %Character{} = character}) do
    case GuildSystem.group_of(guid) do
      %Group{} = group -> notify_event(group, :signed_off, [character.internal.name])
      nil -> :ok
    end
  end

  def signed_off(_state), do: :ok

  defp membership(guid) do
    case GuildSystem.group_of(guid) do
      %Group{id: id} = group -> {id, Guild.member(group, guid).rank}
      nil -> {0, 0}
    end
  end

  def chat(%{guid: guid, character: %Character{} = character} = state, type, language, message) when type in [3, 4] do
    with %Group{} = group <- GuildSystem.group_of(guid),
         :ok <- chat_allowed(group, guid, type) do
      packet = %Message.SmsgMessagechat{
        chat_type: type,
        language: language,
        sender_guid: guid,
        message: message,
        channel_name: nil,
        player_rank: 0,
        tag: StatusLogic.tag(character)
      }

      permission = if(type == 3, do: :guild_listen, else: :officer_listen)
      deliver_chat(group, permission, packet)
    end

    state
  end

  defp deliver_chat(group, permission, packet) do
    Enum.each(group.members, fn {guid, _member} ->
      if Guild.right?(group, guid, permission), do: Network.send_packet(packet, guid)
    end)
  end

  defp chat_allowed(group, guid, 3) do
    if Guild.right?(group, guid, :guild_speak), do: :ok, else: {:error, :permissions}
  end

  defp chat_allowed(group, guid, 4) do
    if Guild.right?(group, guid, :officer_speak), do: :ok, else: {:error, :permissions}
  end

  defp send_roster(group, viewer_guid) do
    officer_notes? = Guild.right?(group, viewer_guid, :view_officer_note)

    entries =
      group.members
      |> Enum.map(fn {_guid, member} -> roster_entry(member, officer_notes?) end)
      |> Enum.sort_by(&{&1.rank, &1.name})

    Network.send_packet(%Message.SmsgGuildRoster{guild: group, entries: entries}, viewer_guid)
  end

  defp roster_entry(%Member{} = member, officer_notes?) do
    online? = Entity.online?(member.guid)

    metadata =
      if(online?, do: Metadata.query(member.guid, [:level, :class, :area]), else: offline_facts(member.guid)) || %{}

    %Entry{
      guid: member.guid,
      name: member.name,
      rank: member.rank,
      level: Map.get(metadata, :level) || member.level,
      class: Map.get(metadata, :class) || member.class,
      area: Map.get(metadata, :area) || member.area,
      online?: online?,
      offline_days: 0.0,
      public_note: member.public_note,
      officer_note: if(officer_notes?, do: member.officer_note, else: "")
    }
  end

  defp offline_facts(guid) do
    case CharacterStore.get(Guid.low_guid(guid)) do
      %Character{} = character ->
        %{level: character.unit.level, class: character.unit.class, area: character.internal.area}

      _ ->
        %{}
    end
  end

  defp notify(state, group, event, descriptions) do
    notify_event(group, event, descriptions)
    state
  end

  defp notify_event(group, event, descriptions) do
    packet = %Message.SmsgGuildEvent{event: event, descriptions: descriptions}
    Enum.each(group.members, fn {guid, _member} -> Network.send_packet(packet, guid) end)
  end

  defp notify_member(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, :sync_guild_membership)
      _ -> sync_offline_member(guid)
    end
  end

  defp sync_offline_member(guid) do
    case CharacterStore.get(Guid.low_guid(guid)) do
      %Character{} = character -> character |> attach() |> CharacterStore.put()
      _ -> :ok
    end
  end

  defp named_member(guid, name) do
    with %Group{} = group <- GuildSystem.group_of(guid), do: Guild.member_by_name(group, name)
  end

  def member(%Character{} = character) do
    %Member{
      guid: character.object.guid,
      name: character.internal.name,
      race: character.unit.race,
      class: character.unit.class,
      level: character.unit.level,
      area: character.internal.area || 0
    }
  end

  defp send_result(command, name, reason) do
    Network.send_packet(%CommandResult{command: command, name: name, result: reason})
  end
end
