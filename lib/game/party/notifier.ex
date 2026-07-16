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
        %{name: member.name, guid: member.guid, online?: online?(member.guid), flags: member.flags}
      end

    Network.send_packet(
      %Message.SmsgGroupList{
        members: members,
        leader: group.leader,
        loot_method: group.loot_method,
        master_looter: group.master_looter,
        loot_threshold: group.loot_threshold
      },
      guid
    )
  end

  def send_empty_group_list(guid) do
    notify_leader_status(guid, false)
    Network.send_packet(%Message.SmsgGroupList{}, guid)
  end

  def broadcast(%Group{} = group, packet, opts \\ []) do
    except = Keyword.get(opts, :except)

    Enum.each(group.members, fn member ->
      if member.guid != except do
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

  defp notify_leader_status(guid, leader?) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:party_leader_changed, leader?})
      _ -> :ok
    end
  end
end
