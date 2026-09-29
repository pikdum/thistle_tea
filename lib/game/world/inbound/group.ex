defmodule ThistleTea.Game.World.Inbound.Group do
  @moduledoc "Handles decoded party, raid, and meeting stone client messages."

  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Party.Group
  alias ThistleTea.Game.Core.Party.MemberStats
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.World.Entity.Player.Groups
  alias ThistleTea.Game.World.Entity.Player.MeetingStones
  alias ThistleTea.Game.World.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.Party.Notifier

  def messages do
    [
      Message.CmsgGroupAccept,
      Message.CmsgGroupAssistantLeader,
      Message.CmsgGroupChangeSubGroup,
      Message.CmsgGroupDecline,
      Message.CmsgGroupDisband,
      Message.CmsgGroupInvite,
      Message.CmsgGroupRaidConvert,
      Message.CmsgGroupSetLeader,
      Message.CmsgGroupSwapSubGroup,
      Message.CmsgGroupUninvite,
      Message.CmsgGroupUninviteGuid,
      Message.CmsgLootMethod,
      Message.CmsgMeetingstoneInfo,
      Message.CmsgMeetingstoneJoin,
      Message.CmsgMeetingstoneLeave,
      Message.CmsgRequestPartyMemberStats,
      Message.MsgMinimapPing,
      Message.MsgRaidReadyCheck,
      Message.MsgRaidTargetUpdate,
      Message.MsgRandomRoll
    ]
  end

  def handle(%Message.CmsgGroupAccept{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.accept(guid, character.internal.name) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def handle(%Message.CmsgGroupAccept{}, state), do: state

  def handle(%Message.CmsgGroupAssistantLeader{guid: guid, enabled?: enabled?}, state),
    do: Groups.set_assistant(state, guid, enabled?)

  def handle(%Message.CmsgGroupChangeSubGroup{name: name, subgroup: subgroup}, state),
    do: Groups.change_subgroup(state, name, subgroup)

  def handle(%Message.CmsgGroupDecline{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.decline(guid) do
      {:ok, inviter_guid} ->
        Outbound.send_packet(%Message.SmsgGroupDecline{name: character.internal.name}, inviter_guid)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def handle(%Message.CmsgGroupDecline{}, state), do: state

  def handle(%Message.CmsgGroupDisband{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.leave(guid) do
      {:ok, outcome} ->
        Outbound.send_packet(%Result{
          operation: Result.op_leave(),
          name: character.internal.name,
          result: Result.code(:ok)
        })

        Notifier.notify_removal(outcome, guid, false)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def handle(%Message.CmsgGroupDisband{}, state), do: state

  def handle(%Message.CmsgGroupInvite{name: name}, state), do: Groups.invite(state, name)

  def handle(%Message.CmsgGroupRaidConvert{}, state), do: Groups.convert_raid(state)

  def handle(%Message.CmsgGroupSetLeader{guid: new_leader_guid}, %{ready: true, guid: guid} = state) do
    case PartySystem.set_leader(guid, new_leader_guid) do
      {:ok, group} ->
        Notifier.broadcast(group, %Message.SmsgGroupSetLeader{name: Notifier.leader_name(group)})
        Notifier.send_group_list(group)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def handle(%Message.CmsgGroupSetLeader{}, state), do: state

  def handle(%Message.CmsgGroupSwapSubGroup{first: first, second: second}, state),
    do: Groups.swap_subgroups(state, first, second)

  def handle(%Message.CmsgGroupUninvite{name: name}, %{ready: true, guid: guid} = state) do
    case resolve_guid(guid, name) do
      nil -> send_result(name, :target_not_in_group)
      target_guid -> uninvite(guid, target_guid, name)
    end

    state
  end

  def handle(%Message.CmsgGroupUninvite{}, state), do: state

  def handle(%Message.CmsgGroupUninviteGuid{guid: target_guid}, %{ready: true, guid: guid} = state) do
    uninvite(guid, target_guid, member_name(guid, target_guid))
    state
  end

  def handle(%Message.CmsgGroupUninviteGuid{}, state), do: state

  def handle(
        %Message.CmsgLootMethod{loot_method: method, master_looter: master_looter, loot_threshold: threshold},
        %{ready: true, guid: guid} = state
      )
      when method in 0..4 and threshold in 0..6 do
    case PartySystem.set_loot(guid, method, master_looter, threshold) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def handle(%Message.CmsgLootMethod{}, state), do: state

  def handle(%Message.CmsgMeetingstoneInfo{}, state), do: MeetingStones.request(state, :info)

  def handle(%Message.CmsgMeetingstoneJoin{guid: guid}, state), do: MeetingStones.join(state, guid)

  def handle(%Message.CmsgMeetingstoneLeave{}, state), do: MeetingStones.request(state, :leave)

  def handle(%Message.CmsgRequestPartyMemberStats{guid: target_guid}, %{ready: true, guid: guid} = state) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{} <- Party.member(group, target_guid) do
      send_stats(guid, target_guid)
    end

    state
  end

  def handle(%Message.CmsgRequestPartyMemberStats{}, state), do: state

  def handle(%Message.MsgMinimapPing{x: x, y: y}, %{ready: true, guid: guid} = state) do
    case PartySystem.group_of(guid) do
      %Group{} = group ->
        Notifier.broadcast(group, %Message.MsgMinimapPingResponse{guid: guid, x: x, y: y}, except: guid)

      _ ->
        :ok
    end

    state
  end

  def handle(%Message.MsgMinimapPing{}, state), do: state

  def handle(%Message.MsgRaidReadyCheck{ready?: ready?}, state), do: Groups.ready_check(state, ready?)

  def handle(%Message.MsgRaidTargetUpdate{icon: icon, target: target}, state),
    do: Groups.target_icon(state, icon, target)

  def handle(%Message.MsgRandomRoll{minimum: minimum, maximum: maximum}, state) do
    Groups.random_roll(state, minimum, maximum)
  end

  defp resolve_guid(guid, name) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{guid: target_guid} <- Party.member_by_name(group, name) do
      target_guid
    else
      _ -> Metadata.find_guid_by(:name, name)
    end
  end

  defp uninvite(remover_guid, target_guid, name) do
    case PartySystem.uninvite(remover_guid, target_guid) do
      {:ok, :invite_cancelled} -> :ok
      {:ok, outcome} -> Notifier.notify_removal(outcome, target_guid, true)
      {:error, reason} -> send_result(name, reason)
    end
  end

  defp send_result(name, reason) do
    Outbound.send_packet(%Result{operation: Result.op_leave(), name: name, result: Result.code(reason)})
  end

  defp member_name(guid, target_guid) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{name: name} <- Party.member(group, target_guid) do
      name
    else
      _ -> ""
    end
  end

  defp send_stats(requester_guid, target_guid) do
    case EntityRegistry.whereis(target_guid) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:request_party_stats, requester_guid})

      _ ->
        Outbound.send_packet(struct(Message.SmsgPartyMemberStatsFull, MemberStats.offline(target_guid)))
    end
  end
end
