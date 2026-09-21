defmodule ThistleTea.Game.Party.Notifier do
  @moduledoc """
  Sends group packets (roster updates, destruction, member stats) to every
  online member of a party group.
  """
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.MemberStats
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def send_group_list(%Group{} = group) do
    Enum.each(group.members, fn member -> send_group_list(group, member.guid) end)
  end

  def send_group_list(%Group{} = group, guid) do
    notify_leader_status(guid, group.leader == guid)

    members =
      for member <- group.members, member.guid != guid do
        %{name: member.name, guid: member.guid, online?: online?(member.guid), flags: Party.member_flags(member)}
      end

    Network.send_packet(
      %Message.SmsgGroupList{
        group_type: if(group.raid?, do: 1, else: 0),
        own_flags: own_flags(group, guid),
        members: members,
        leader: group.leader,
        loot_method: group.loot_method,
        master_looter: group.master_looter,
        loot_threshold: group.loot_threshold
      },
      guid
    )

    if map_size(group.icons) > 0 do
      Network.send_packet(%Message.MsgRaidTargetUpdateResponse{icons: Enum.sort(group.icons)}, guid)
    end
  end

  def send_empty_group_list(guid) do
    notify_leader_status(guid, false)
    Network.send_packet(%Message.SmsgGroupList{}, guid)
  end

  def broadcast(%Group{} = group, packet, opts \\ []) do
    except = Keyword.get(opts, :except)
    subgroup = Keyword.get(opts, :subgroup)

    Enum.each(group.members, fn member ->
      if member.guid != except and (subgroup == nil or member.subgroup == subgroup) do
        Network.send_packet(packet, member.guid)
      end
    end)
  end

  def notify_removal({:disbanded, %Group{} = group}, _removed_guid, _kicked?) do
    Enum.each(group.members, fn member ->
      Network.send_packet(%Message.SmsgGroupDestroyed{}, member.guid)
      send_empty_group_list(member.guid)
    end)
  end

  def notify_removal({:removed, %Group{} = group, leader_changed?}, removed_guid, kicked?) do
    if kicked? do
      Network.send_packet(%Message.SmsgGroupUninvite{}, removed_guid)
    end

    send_empty_group_list(removed_guid)

    if leader_changed? do
      broadcast(group, %Message.SmsgGroupSetLeader{name: leader_name(group)})
    end

    send_group_list(group)
  end

  def broadcast_stats(guid, character) do
    case PartySystem.group_of(guid) do
      %Group{} = group ->
        packet = struct(Message.SmsgPartyMemberStats, MemberStats.from_character(character))
        broadcast(group, packet, except: guid)

      _ ->
        :ok
    end
  end

  def leader_name(%Group{} = group) do
    case Party.member(group, group.leader) do
      %{name: name} -> name
      _ -> ""
    end
  end

  defp online?(guid), do: is_pid(EntityRegistry.whereis(guid))

  defp own_flags(group, guid) do
    case Party.member(group, guid) do
      %Party.Member{} = member -> Party.member_flags(member)
      _ -> 0
    end
  end

  defp notify_leader_status(guid, leader?) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:party_leader_changed, leader?})
        GenServer.cast(pid, :party_visibility_changed)

      _ ->
        :ok
    end
  end
end
