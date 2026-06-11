defmodule ThistleTea.Game.Party do
  @moduledoc """
  Pure group/party state and logic: pending invites, membership, leadership,
  and loot settings. No processes, no packets — the boundary lives in
  `ThistleTea.Game.World.System.Party`.
  """

  defmodule Member do
    @moduledoc false
    defstruct [:guid, :name, flags: 0]
  end

  defmodule Group do
    @moduledoc false
    defstruct [:id, :leader, members: [], loot_method: 3, master_looter: 0, loot_threshold: 2]
  end

  defstruct groups: %{}, member_index: %{}, invites: %{}, next_id: 1

  @max_members 5
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def max_members, do: @max_members

  def group_of(%__MODULE__{} = party, guid) do
    case Map.fetch(party.member_index, guid) do
      {:ok, group_id} -> Map.get(party.groups, group_id)
      :error -> nil
    end
  end

  def in_group?(%__MODULE__{} = party, guid), do: Map.has_key?(party.member_index, guid)

  def invited?(%__MODULE__{} = party, guid), do: Map.has_key?(party.invites, guid)

  def member(%Group{members: members}, guid), do: Enum.find(members, &(&1.guid == guid))

  def member_by_name(%Group{members: members}, name), do: Enum.find(members, &(&1.name == name))

  def leader?(%Group{leader: leader}, guid), do: leader == guid

  def same_team?(race_a, race_b) do
    (race_a in @alliance_races and race_b in @alliance_races) or
      (race_a in @horde_races and race_b in @horde_races)
  end

  def invite(%__MODULE__{} = party, inviter_guid, inviter_name, invitee_guid) do
    group = group_of(party, inviter_guid)

    cond do
      in_group?(party, invitee_guid) or invited?(party, invitee_guid) ->
        {:error, :already_in_group}

      group != nil and not leader?(group, inviter_guid) ->
        {:error, :not_leader}

      group != nil and full?(group) ->
        {:error, :group_full}

      true ->
        invite = %{inviter: inviter_guid, inviter_name: inviter_name}
        {:ok, %{party | invites: Map.put(party.invites, invitee_guid, invite)}}
    end
  end

  def accept(%__MODULE__{} = party, invitee_guid, invitee_name) do
    case Map.pop(party.invites, invitee_guid) do
      {nil, _invites} ->
        {:error, :not_invited}

      {invite, invites} ->
        party = %{party | invites: invites}
        invitee = %Member{guid: invitee_guid, name: invitee_name}
        join_group(party, group_of(party, invite.inviter), invite, invitee)
    end
  end

  def decline(%__MODULE__{} = party, invitee_guid) do
    case Map.pop(party.invites, invitee_guid) do
      {nil, _invites} -> {:error, :not_invited}
      {invite, invites} -> {:ok, invite.inviter, %{party | invites: invites}}
    end
  end

  def leave(%__MODULE__{} = party, guid) do
    case group_of(party, guid) do
      nil -> {:error, :not_in_group}
      group -> remove_member(party, group, guid)
    end
  end

  def uninvite(%__MODULE__{} = party, remover_guid, target_guid) do
    group = group_of(party, remover_guid)

    cond do
      group == nil ->
        {:error, :not_in_group}

      not leader?(group, remover_guid) ->
        {:error, :not_leader}

      invited_by?(party, target_guid, remover_guid) ->
        {:ok, :invite_cancelled, %{party | invites: Map.delete(party.invites, target_guid)}}

      member(group, target_guid) == nil ->
        {:error, :target_not_in_group}

      true ->
        remove_member(party, group, target_guid)
    end
  end

  def set_leader(%__MODULE__{} = party, requester_guid, new_leader_guid) do
    group = group_of(party, requester_guid)

    cond do
      group == nil ->
        {:error, :not_in_group}

      not leader?(group, requester_guid) ->
        {:error, :not_leader}

      member(group, new_leader_guid) == nil ->
        {:error, :target_not_in_group}

      true ->
        group = %{group | leader: new_leader_guid}
        {:ok, group, put_group(party, group)}
    end
  end

  def set_loot(%__MODULE__{} = party, requester_guid, method, master_looter, threshold) do
    group = group_of(party, requester_guid)

    cond do
      group == nil ->
        {:error, :not_in_group}

      not leader?(group, requester_guid) ->
        {:error, :not_leader}

      true ->
        group = %{group | loot_method: method, master_looter: master_looter, loot_threshold: threshold}
        {:ok, group, put_group(party, group)}
    end
  end

  defp join_group(party, nil, invite, invitee) do
    inviter = %Member{guid: invite.inviter, name: invite.inviter_name}

    group = %Group{
      id: party.next_id,
      leader: invite.inviter,
      members: [inviter, invitee]
    }

    party = %{party | next_id: party.next_id + 1}
    {:ok, group, party |> put_group(group) |> index_members(group)}
  end

  defp join_group(_party, %Group{members: members}, _invite, _invitee) when length(members) >= @max_members do
    {:error, :group_full}
  end

  defp join_group(party, group, _invite, invitee) do
    group = %{group | members: group.members ++ [invitee]}
    {:ok, group, party |> put_group(group) |> index_members(group)}
  end

  defp remove_member(party, group, guid) do
    remaining = Enum.reject(group.members, &(&1.guid == guid))

    if length(remaining) < 2 do
      party = %{
        party
        | groups: Map.delete(party.groups, group.id),
          member_index: Map.drop(party.member_index, Enum.map(group.members, & &1.guid))
      }

      {:ok, {:disbanded, group}, party}
    else
      leader_changed? = group.leader == guid
      leader = if leader_changed?, do: hd(remaining).guid, else: group.leader
      group = %{group | members: remaining, leader: leader}

      party = %{put_group(party, group) | member_index: Map.delete(party.member_index, guid)}
      {:ok, {:removed, group, leader_changed?}, party}
    end
  end

  defp invited_by?(party, target_guid, inviter_guid) do
    case Map.get(party.invites, target_guid) do
      %{inviter: ^inviter_guid} -> true
      _ -> false
    end
  end

  defp full?(%Group{members: members}), do: length(members) >= @max_members

  defp put_group(party, group), do: %{party | groups: Map.put(party.groups, group.id, group)}

  defp index_members(party, group) do
    Enum.reduce(group.members, party, fn member, party ->
      %{party | member_index: Map.put(party.member_index, member.guid, group.id)}
    end)
  end
end
