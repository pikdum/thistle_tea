defmodule ThistleTea.Game.World.Entity.Player.Groups do
  @moduledoc """
  Player-owner party requests: invitations and their answers, leaving and
  removing members, leader, loot, and raid management, member stats, target
  markers, minimap pings, ready checks, and random rolls. Membership
  mutations are serialized by the party system before projection.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Party.Group
  alias ThistleTea.Game.Core.Party.Member
  alias ThistleTea.Game.Core.Party.MemberStats
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.Party.Notifier

  def random_roll(%{ready: true, guid: guid} = state, minimum, maximum)
      when minimum in 0..1_000_000 and maximum in 0..1_000_000 and minimum <= maximum do
    packet = %Message.MsgRandomRollResponse{
      minimum: minimum,
      maximum: maximum,
      result: Math.random_int(minimum, maximum),
      guid: guid
    }

    case PartySystem.group_of(guid) do
      %Group{} = group -> Notifier.broadcast(group, packet)
      nil -> Outbound.send_packet(packet, guid)
    end

    state
  end

  def random_roll(state, _minimum, _maximum), do: state

  def accept(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    case PartySystem.accept(guid, character.internal.name) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def accept(state), do: state

  def decline(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    case PartySystem.decline(guid) do
      {:ok, inviter_guid} ->
        Outbound.send_packet(%Message.SmsgGroupDecline{name: character.internal.name}, inviter_guid)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def decline(state), do: state

  def leave(%{ready: true, guid: guid, character: %Character{} = character} = state) do
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

  def leave(state), do: state

  def set_leader(%{ready: true, guid: guid} = state, new_leader_guid) do
    case PartySystem.set_leader(guid, new_leader_guid) do
      {:ok, group} ->
        Notifier.broadcast(group, %Message.SmsgGroupSetLeader{name: Notifier.leader_name(group)})
        Notifier.send_group_list(group)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def set_leader(state, _new_leader_guid), do: state

  def uninvite_name(%{ready: true, guid: guid} = state, name) do
    case member_guid(guid, name) do
      nil -> send_leave_result(name, :target_not_in_group)
      target_guid -> uninvite(guid, target_guid, name)
    end

    state
  end

  def uninvite_name(state, _name), do: state

  def uninvite_guid(%{ready: true, guid: guid} = state, target_guid) do
    uninvite(guid, target_guid, member_name(guid, target_guid))
    state
  end

  def uninvite_guid(state, _target_guid), do: state

  def set_loot(%{ready: true, guid: guid} = state, method, master_looter, threshold)
      when method in 0..4 and threshold in 0..6 do
    case PartySystem.set_loot(guid, method, master_looter, threshold) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def set_loot(state, _method, _master_looter, _threshold), do: state

  def request_member_stats(%{ready: true, guid: guid} = state, target_guid) do
    with %Group{} = group <- PartySystem.group_of(guid),
         %Member{} <- Party.member(group, target_guid) do
      send_member_stats(guid, target_guid)
    end

    state
  end

  def request_member_stats(state, _target_guid), do: state

  def minimap_ping(%{ready: true, guid: guid} = state, x, y) do
    case PartySystem.group_of(guid) do
      %Group{} = group ->
        Notifier.broadcast(group, %Message.MsgMinimapPingResponse{guid: guid, x: x, y: y}, except: guid)

      _ ->
        :ok
    end

    state
  end

  def minimap_ping(state, _x, _y), do: state

  def invite(%{ready: true, guid: guid, character: %Character{} = character} = state, name) do
    name = String.capitalize(name)
    invitee_guid = Metadata.find_guid_by(:name, name)

    result =
      cond do
        invitee_guid == nil or invitee_guid == guid -> {:error, :bad_player_name}
        not same_team?(character.unit.race, invitee_guid) -> {:error, :wrong_faction}
        SocialStore.ignores?(invitee_guid, guid) -> {:error, :ignoring_you}
        true -> PartySystem.invite(guid, character.internal.name, invitee_guid)
      end

    reason =
      case result do
        :ok ->
          Outbound.send_packet(%Message.SmsgGroupInvite{name: character.internal.name}, invitee_guid)
          :ok

        {:error, reason} ->
          reason
      end

    Outbound.send_packet(%Result{operation: Result.op_invite(), name: name, result: Result.code(reason)}, guid)
    state
  end

  def invite(state, _name), do: state

  def convert_raid(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    if !MapTemplate.battleground?(character.internal.world.map_id) do
      with {:ok, group} <- PartySystem.convert_raid(guid) do
        Outbound.send_packet(%Result{operation: Result.op_invite(), name: "", result: Result.code(:ok)}, guid)
        Notifier.send_group_list(group)
      end
    end

    state
  end

  def convert_raid(state), do: state

  def change_subgroup(%{ready: true, guid: guid} = state, name, subgroup) do
    with %Member{guid: target} <- named_member(guid, name),
         {:ok, group} <- PartySystem.change_subgroup(guid, target, subgroup) do
      Notifier.send_group_list(group)
    end

    state
  end

  def change_subgroup(state, _name, _subgroup), do: state

  def swap_subgroups(%{ready: true, guid: guid} = state, first_name, second_name) do
    with %Member{guid: first} <- named_member(guid, first_name),
         %Member{guid: second} <- named_member(guid, second_name),
         {:ok, group} <- PartySystem.swap_subgroups(guid, first, second) do
      Notifier.send_group_list(group)
    end

    state
  end

  def swap_subgroups(state, _first, _second), do: state

  def set_assistant(%{ready: true, guid: guid} = state, target, enabled?) do
    with pid when is_pid(pid) <- Entity.pid(target),
         {:ok, group} <- PartySystem.set_assistant(guid, target, enabled?) do
      Notifier.send_group_list(group)
    end

    state
  end

  def set_assistant(state, _target, _enabled?), do: state

  def target_icon(%{ready: true, guid: guid} = state, 0xFF, _target) do
    with %Group{} = group <- PartySystem.group_of(guid) do
      Outbound.send_packet(%Message.MsgRaidTargetUpdateResponse{icons: Enum.sort(group.icons)}, guid)
    end

    state
  end

  def target_icon(%{ready: true, guid: guid} = state, icon, target) do
    with {:ok, group, changes} <- PartySystem.set_icon(guid, icon, target) do
      Enum.each(changes, fn {id, target} ->
        Notifier.broadcast(group, %Message.MsgRaidTargetUpdateResponse{icon: id, target: target})
      end)
    end

    state
  end

  def target_icon(state, _icon, _target), do: state

  def ready_check(%{ready: true, guid: guid} = state, nil) do
    with %Group{} = group <- PartySystem.group_of(guid),
         true <- Party.manager?(group, guid) do
      Notifier.broadcast(group, %Message.MsgRaidReadyCheckResponse{})

      Enum.each(group.members, &report_offline_member(&1, group.leader))
    end

    state
  end

  def ready_check(%{ready: true, guid: guid} = state, ready?) when is_boolean(ready?) do
    with %Group{} = group <- PartySystem.group_of(guid) do
      Outbound.send_packet(%Message.MsgRaidReadyCheckResponse{guid: guid, ready?: ready?}, group.leader)
    end

    state
  end

  def ready_check(state, _ready?), do: state

  defp report_offline_member(%Member{guid: guid}, leader) do
    if !Entity.online?(guid) do
      Outbound.send_packet(%Message.MsgRaidReadyCheckResponse{guid: guid, ready?: false}, leader)
    end
  end

  defp member_guid(guid, name) do
    case named_member(guid, name) do
      %Member{guid: target_guid} -> target_guid
      _ -> Metadata.find_guid_by(:name, name)
    end
  end

  defp member_name(guid, target_guid) do
    with %Group{} = group <- PartySystem.group_of(guid),
         %Member{name: name} <- Party.member(group, target_guid) do
      name
    else
      _ -> ""
    end
  end

  defp uninvite(remover_guid, target_guid, name) do
    case PartySystem.uninvite(remover_guid, target_guid) do
      {:ok, :invite_cancelled} -> :ok
      {:ok, outcome} -> Notifier.notify_removal(outcome, target_guid, true)
      {:error, reason} -> send_leave_result(name, reason)
    end
  end

  defp send_leave_result(name, reason) do
    Outbound.send_packet(%Result{operation: Result.op_leave(), name: name, result: Result.code(reason)})
  end

  defp send_member_stats(requester_guid, target_guid) do
    case EntityRegistry.whereis(target_guid) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:request_party_stats, requester_guid})
      _ -> Outbound.send_packet(struct(Message.SmsgPartyMemberStatsFull, MemberStats.offline(target_guid)))
    end
  end

  defp named_member(guid, name) do
    with %Group{} = group <- PartySystem.group_of(guid), do: Party.member_by_name(group, name)
  end

  defp same_team?(race, invitee_guid) do
    case Metadata.query(invitee_guid, [:race]) do
      %{race: target_race} when is_integer(target_race) -> Party.same_team?(race, target_race)
      _ -> false
    end
  end
end
