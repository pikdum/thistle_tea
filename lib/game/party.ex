defmodule ThistleTea.Game.Party do
  @moduledoc """
  Pure group/party state and logic: pending invites, membership, leadership,
  and loot settings. No processes, no packets — the boundary lives in
  `ThistleTea.Game.World.System.Party`.
  """

  defmodule Member do
    @moduledoc false
    defstruct [:guid, :name, subgroup: 0, assistant?: false]
  end

  defmodule Group do
    @moduledoc false
    defstruct [
      :id,
      :leader,
      members: [],
      raid?: false,
      icons: %{},
      loot_method: 3,
      master_looter: 0,
      loot_threshold: 2,
      looter: 0
    ]
  end

  defstruct groups: %{}, member_index: %{}, invites: %{}, next_id: 1

  @max_members 5
  @raid_subgroups 8
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def max_members, do: @max_members
  def max_members(%Group{raid?: true}), do: @max_members * @raid_subgroups
  def max_members(%Group{}), do: @max_members

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

  def assistant?(%Group{raid?: true} = group, guid), do: match?(%Member{assistant?: true}, member(group, guid))
  def assistant?(%Group{}, _guid), do: false

  def manager?(%Group{} = group, guid), do: leader?(group, guid) or assistant?(group, guid)

  def member_flags(%Member{subgroup: subgroup, assistant?: assistant?}) do
    Bitwise.bor(subgroup, if(assistant?, do: 0x80, else: 0))
  end

  def subgroup_members(%Group{} = group, guid) do
    case member(group, guid) do
      %Member{subgroup: subgroup} -> Enum.filter(group.members, &(&1.subgroup == subgroup))
      _ -> []
    end
  end

  def same_team?(race_a, race_b) do
    (race_a in @alliance_races and race_b in @alliance_races) or
      (race_a in @horde_races and race_b in @horde_races)
  end

  def invite(%__MODULE__{} = party, inviter_guid, inviter_name, invitee_guid) do
    group = group_of(party, inviter_guid)

    cond do
      unavailable_for_invite?(party, inviter_guid, invitee_guid) ->
        {:error, :already_in_group}

      group != nil and not manager?(group, inviter_guid) ->
        {:error, :not_leader}

      group != nil and full?(group) ->
        {:error, :group_full}

      true ->
        invite = %{inviter: inviter_guid, inviter_name: inviter_name, group_id: if(group, do: group.id)}
        {:ok, %{party | invites: Map.put(party.invites, invitee_guid, invite)}}
    end
  end

  defp unavailable_for_invite?(party, inviter_guid, invitee_guid) do
    in_group?(party, invitee_guid) or invited?(party, invitee_guid) or invited?(party, inviter_guid)
  end

  def accept(%__MODULE__{} = party, invitee_guid, invitee_name) do
    if in_group?(party, invitee_guid),
      do: {:error, :already_in_group},
      else: accept_invite(party, invitee_guid, invitee_name)
  end

  defp accept_invite(party, invitee_guid, invitee_name) do
    case Map.pop(party.invites, invitee_guid) do
      {nil, _invites} ->
        {:error, :not_invited}

      {invite, invites} ->
        party = %{party | invites: invites}
        invitee = %Member{guid: invitee_guid, name: invitee_name}

        case invited_group(party, invite) do
          :disbanded -> {:error, :not_invited}
          group -> join_group(party, group, invite, invitee)
        end
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

      not manager?(group, remover_guid) or group.leader == target_guid ->
        {:error, :not_leader}

      invited_to_group?(party, target_guid, group) ->
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

  def update_looter(%__MODULE__{} = party, group_id, eligible_guids) do
    case Map.get(party.groups, group_id) do
      %Group{} = group ->
        next = next_looter(Enum.map(group.members, & &1.guid), group.looter, eligible_guids)
        {next, put_group(party, %{group | looter: next || 0})}

      _ ->
        {nil, party}
    end
  end

  defp next_looter([], _current, _eligible), do: nil

  defp next_looter(order, current, eligible) do
    eligible = MapSet.new(eligible)
    index = Enum.find_index(order, &(&1 == current)) || -1
    count = length(order)

    0..(count - 1)
    |> Enum.map(fn offset -> Enum.at(order, rem(index + 1 + offset, count)) end)
    |> Enum.find(&MapSet.member?(eligible, &1))
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

  def convert_raid(%__MODULE__{} = party, requester_guid) do
    with {:ok, group} <- managed_group(party, requester_guid),
         true <- leader?(group, requester_guid) do
      updated(party, %{group | raid?: true})
    else
      false -> {:error, :not_leader}
      error -> error
    end
  end

  def set_assistant(%__MODULE__{} = party, requester_guid, target_guid, enabled?) when is_boolean(enabled?) do
    with {:ok, group} <- managed_raid(party, requester_guid),
         true <- leader?(group, requester_guid) and target_guid != requester_guid,
         {:ok, target} <- fetch_member(group, target_guid) do
      updated(party, replace_member(group, %{target | assistant?: enabled?}))
    else
      false -> {:error, :not_leader}
      error -> error
    end
  end

  def change_subgroup(%__MODULE__{} = party, requester_guid, target_guid, subgroup) when subgroup in 0..7 do
    with {:ok, group} <- managed_raid(party, requester_guid),
         {:ok, target} <- fetch_member(group, target_guid),
         true <- target.subgroup == subgroup or subgroup_size(group, subgroup) < @max_members do
      updated(party, replace_member(group, %{target | subgroup: subgroup}))
    else
      false -> {:error, :group_full}
      error -> error
    end
  end

  def change_subgroup(%__MODULE__{}, _requester_guid, _target_guid, _subgroup), do: {:error, :invalid_subgroup}

  def swap_subgroups(%__MODULE__{} = party, requester_guid, first_guid, second_guid) do
    with {:ok, group} <- managed_raid(party, requester_guid),
         {:ok, first} <- fetch_member(group, first_guid),
         {:ok, second} <- fetch_member(group, second_guid) do
      group =
        group
        |> replace_member(%{first | subgroup: second.subgroup})
        |> replace_member(%{second | subgroup: first.subgroup})

      updated(party, group)
    end
  end

  def set_icon(%__MODULE__{} = party, requester_guid, icon, target_guid)
      when icon in 0..7 and is_integer(target_guid) and target_guid >= 0 do
    with {:ok, group} <- managed_group(party, requester_guid) do
      cleared = for {id, guid} <- group.icons, guid == target_guid and id != icon, do: {id, 0}
      icons = Map.drop(group.icons, Enum.map(cleared, &elem(&1, 0)))
      icons = if target_guid == 0, do: Map.delete(icons, icon), else: Map.put(icons, icon, target_guid)
      group = %{group | icons: icons}
      {:ok, group, Enum.sort(cleared) ++ [{icon, target_guid}], put_group(party, group)}
    end
  end

  def set_icon(%__MODULE__{}, _requester_guid, _icon, _target_guid), do: {:error, :invalid_icon}

  defp managed_group(party, requester_guid) do
    case group_of(party, requester_guid) do
      nil -> {:error, :not_in_group}
      group -> if manager?(group, requester_guid), do: {:ok, group}, else: {:error, :not_leader}
    end
  end

  defp managed_raid(party, requester_guid) do
    case managed_group(party, requester_guid) do
      {:ok, %Group{raid?: true} = group} -> {:ok, group}
      {:ok, %Group{}} -> {:error, :not_raid}
      error -> error
    end
  end

  defp fetch_member(group, guid) do
    case member(group, guid) do
      %Member{} = member -> {:ok, member}
      _ -> {:error, :target_not_in_group}
    end
  end

  defp updated(party, group), do: {:ok, group, put_group(party, group)}

  defp replace_member(group, member) do
    %{group | members: Enum.map(group.members, &if(&1.guid == member.guid, do: member, else: &1))}
  end

  defp subgroup_size(group, subgroup), do: Enum.count(group.members, &(&1.subgroup == subgroup))

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

  defp join_group(party, group, _invite, invitee) do
    if full?(group) do
      {:error, :group_full}
    else
      subgroup = Enum.find(0..(@raid_subgroups - 1), &(subgroup_size(group, &1) < @max_members))
      group = %{group | members: group.members ++ [%{invitee | subgroup: subgroup}]}
      {:ok, group, party |> put_group(group) |> index_members(group)}
    end
  end

  defp remove_member(party, group, guid) do
    remaining = Enum.reject(group.members, &(&1.guid == guid))

    if length(remaining) < 2 do
      party = %{
        party
        | groups: Map.delete(party.groups, group.id),
          member_index: Map.drop(party.member_index, Enum.map(group.members, & &1.guid)),
          invites: remaining_invites(party, group)
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

  defp invited_to_group?(party, target_guid, group) do
    case Map.get(party.invites, target_guid) do
      %{inviter: inviter} = invite -> Map.get(invite, :group_id) == group.id or member(group, inviter) != nil
      _ -> false
    end
  end

  defp invited_group(party, %{group_id: group_id}) when is_integer(group_id),
    do: Map.get(party.groups, group_id, :disbanded)

  defp invited_group(party, invite), do: group_of(party, invite.inviter)

  defp remaining_invites(party, group) do
    Map.reject(party.invites, fn {_guid, invite} ->
      Map.get(invite, :group_id) == group.id or member(group, invite.inviter) != nil
    end)
  end

  defp full?(%Group{members: members} = group), do: length(members) >= max_members(group)

  defp put_group(party, group), do: %{party | groups: Map.put(party.groups, group.id, group)}

  defp index_members(party, group) do
    Enum.reduce(group.members, party, fn member, party ->
      %{party | member_index: Map.put(party.member_index, member.guid, group.id)}
    end)
  end
end
