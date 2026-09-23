defmodule ThistleTea.Game.Guild do
  @moduledoc """
  Pure guild membership, invitation, rank, and permission transitions.
  The guild system owns this state and projects changes to player owners.
  """
  import Bitwise, only: [|||: 2]

  alias __MODULE__.Group
  alias __MODULE__.Member
  alias __MODULE__.Rank
  alias ThistleTea.Game.Party

  defmodule Member do
    @moduledoc false
    @enforce_keys [:guid, :name, :race, :class, :level]
    defstruct [:guid, :name, :race, :class, :level, area: 0, rank: 4, public_note: "", officer_note: ""]
  end

  defmodule Rank do
    @moduledoc false
    @enforce_keys [:name, :rights]
    defstruct [:name, :rights]
  end

  defmodule Group do
    @moduledoc false
    @enforce_keys [:id, :name, :leader, :members, :ranks]
    defstruct [
      :id,
      :name,
      :leader,
      :members,
      :ranks,
      :created_date,
      motd: "No message set.",
      info: "",
      emblem: {0, 0, 0, 0, 0}
    ]
  end

  defstruct groups: %{}, member_index: %{}, name_index: %{}, invites: %{}, next_id: 1

  @max_name_length 24
  @max_rank_name_length 15
  @right_guild_listen 0x41
  @right_guild_speak 0x42
  @right_officer_listen 0x44
  @right_officer_speak 0x48
  @right_invite 0x50
  @right_remove 0x60
  @right_promote 0xC0
  @right_demote 0x140
  @right_set_motd 0x1040
  @right_edit_public_note 0x2040
  @right_view_officer_note 0x4040
  @right_edit_officer_note 0x8040
  @right_edit_info 0x10040
  @all_rights 0x000FF1FF

  @rights %{
    guild_listen: @right_guild_listen,
    guild_speak: @right_guild_speak,
    officer_listen: @right_officer_listen,
    officer_speak: @right_officer_speak,
    invite: @right_invite,
    remove: @right_remove,
    promote: @right_promote,
    demote: @right_demote,
    set_motd: @right_set_motd,
    edit_public_note: @right_edit_public_note,
    view_officer_note: @right_view_officer_note,
    edit_officer_note: @right_edit_officer_note,
    edit_info: @right_edit_info
  }

  def group_of(%__MODULE__{} = guilds, guid) do
    case Map.fetch(guilds.member_index, guid) do
      {:ok, id} -> Map.get(guilds.groups, id)
      :error -> nil
    end
  end

  def invited?(%__MODULE__{} = guilds, guid), do: Map.has_key?(guilds.invites, guid)

  def group_by_name(%__MODULE__{} = guilds, name) when is_binary(name) do
    case Map.fetch(guilds.name_index, String.downcase(name)) do
      {:ok, id} -> Map.get(guilds.groups, id)
      :error -> nil
    end
  end

  def member(%Group{members: members}, guid), do: Map.get(members, guid)

  def member_by_name(%Group{members: members}, name) when is_binary(name) do
    Enum.find_value(members, fn {_guid, member} ->
      if String.downcase(member.name) == String.downcase(name), do: member
    end)
  end

  def right?(%Group{} = group, guid, permission) when is_map_key(@rights, permission) do
    case member(group, guid) do
      %Member{rank: rank} ->
        rights = Enum.at(group.ranks, rank).rights
        Bitwise.band(rights, Map.fetch!(@rights, permission)) == Map.fetch!(@rights, permission)

      nil ->
        false
    end
  end

  def create(%__MODULE__{} = guilds, %Member{} = founder, name, created_date \\ nil) when is_binary(name) do
    name = String.trim(name)
    key = String.downcase(name)

    cond do
      not valid_name?(name) -> {:error, :invalid_name}
      Map.has_key?(guilds.member_index, founder.guid) -> {:error, :already_in_guild}
      Map.has_key?(guilds.name_index, key) -> {:error, :name_exists}
      true -> create_group(guilds, founder, name, key, created_date)
    end
  end

  def create_from_petition(%__MODULE__{} = guilds, %Member{} = founder, signers, name, created_date)
      when is_list(signers) and is_binary(name) do
    name = String.trim(name)
    key = String.downcase(name)

    cond do
      not valid_name?(name) -> {:error, :invalid_name}
      Map.has_key?(guilds.member_index, founder.guid) -> {:error, :already_in_guild}
      Map.has_key?(guilds.name_index, key) -> {:error, :name_exists}
      not valid_petition_signers?(guilds, founder, signers) -> {:error, :need_more}
      true -> create_group(guilds, founder, name, key, created_date, signers)
    end
  end

  defp create_group(guilds, founder, name, key, created_date, signers \\ []) do
    founder = %{founder | rank: 0}
    members = [founder | Enum.map(signers, &%{&1 | rank: 4})]
    member_map = Map.new(members, &{&1.guid, &1})

    group = %Group{
      id: guilds.next_id,
      name: name,
      created_date: created_date,
      leader: founder.guid,
      members: member_map,
      ranks: default_ranks()
    }

    updated = %{
      guilds
      | groups: Map.put(guilds.groups, group.id, group),
        member_index: Enum.reduce(members, guilds.member_index, &Map.put(&2, &1.guid, group.id)),
        name_index: Map.put(guilds.name_index, key, group.id),
        next_id: group.id + 1
    }

    {:ok, group, updated}
  end

  defp valid_petition_signers?(guilds, founder, signers) do
    length(signers) == 9 and
      length(Enum.uniq_by(signers, & &1.guid)) == length(signers) and
      Enum.all?(signers, fn signer ->
        signer.guid != founder.guid and not Map.has_key?(guilds.member_index, signer.guid) and
          Party.same_team?(founder.race, signer.race)
      end)
  end

  def invite(%__MODULE__{} = guilds, inviter_guid, %Member{} = invitee) do
    group = group_of(guilds, inviter_guid)

    cond do
      group == nil -> {:error, :not_in_guild}
      not right?(group, inviter_guid, :invite) -> {:error, :permissions}
      Map.has_key?(guilds.member_index, invitee.guid) -> {:error, :already_in_guild}
      Map.has_key?(guilds.invites, invitee.guid) -> {:error, :already_invited}
      not Party.same_team?(member(group, inviter_guid).race, invitee.race) -> {:error, :wrong_faction}
      true -> {:ok, group, %{guilds | invites: Map.put(guilds.invites, invitee.guid, group.id)}}
    end
  end

  def accept(%__MODULE__{} = guilds, %Member{} = invitee) do
    with false <- Map.has_key?(guilds.member_index, invitee.guid),
         {:ok, group_id} <- Map.fetch(guilds.invites, invitee.guid),
         %Group{} = group <- Map.get(guilds.groups, group_id),
         true <- Party.same_team?(member(group, group.leader).race, invitee.race) do
      invitee = %{invitee | rank: length(group.ranks) - 1}
      group = %{group | members: Map.put(group.members, invitee.guid, invitee)}

      updated = %{
        guilds
        | groups: Map.put(guilds.groups, group.id, group),
          member_index: Map.put(guilds.member_index, invitee.guid, group.id),
          invites: Map.delete(guilds.invites, invitee.guid)
      }

      {:ok, group, updated}
    else
      true -> {:error, :already_in_guild}
      _ -> {:error, :not_invited}
    end
  end

  def decline(%__MODULE__{} = guilds, guid) do
    case Map.pop(guilds.invites, guid) do
      {nil, _invites} -> {:error, :not_invited}
      {group_id, invites} -> {:ok, group_id, %{guilds | invites: invites}}
    end
  end

  def leave(%__MODULE__{} = guilds, guid) do
    case group_of(guilds, guid) do
      nil -> {:error, :not_in_guild}
      %Group{leader: ^guid, members: members} when map_size(members) == 1 -> disband(guilds, guid)
      %Group{leader: ^guid} -> {:error, :leader_cannot_leave}
      group -> remove_member(guilds, group, guid)
    end
  end

  def remove(%__MODULE__{} = guilds, actor_guid, target_guid) do
    group = group_of(guilds, actor_guid)

    cond do
      group == nil -> {:error, :not_in_guild}
      not right?(group, actor_guid, :remove) -> {:error, :permissions}
      member(group, target_guid) == nil -> {:error, :target_not_in_guild}
      member(group, target_guid).rank <= member(group, actor_guid).rank -> {:error, :rank_too_high}
      true -> remove_member(guilds, group, target_guid)
    end
  end

  defp remove_member(guilds, group, guid) do
    group = %{group | members: Map.delete(group.members, guid)}

    updated = %{
      guilds
      | groups: Map.put(guilds.groups, group.id, group),
        member_index: Map.delete(guilds.member_index, guid)
    }

    {:ok, group, updated}
  end

  def disband(%__MODULE__{} = guilds, actor_guid) do
    case group_of(guilds, actor_guid) do
      %Group{leader: ^actor_guid} = group ->
        members =
          Enum.reduce(group.members, guilds.member_index, fn {guid, _member}, index -> Map.delete(index, guid) end)

        invites = Enum.reject(guilds.invites, fn {_guid, id} -> id == group.id end) |> Map.new()

        updated = %{
          guilds
          | groups: Map.delete(guilds.groups, group.id),
            member_index: members,
            name_index: Map.delete(guilds.name_index, String.downcase(group.name)),
            invites: invites
        }

        {:ok, group, updated}

      nil ->
        {:error, :not_in_guild}

      _group ->
        {:error, :permissions}
    end
  end

  def set_leader(%__MODULE__{} = guilds, actor_guid, target_guid) do
    with %Group{leader: ^actor_guid} = group <- group_of(guilds, actor_guid),
         %Member{} = target <- member(group, target_guid) do
      former = member(group, actor_guid)

      members =
        group.members
        |> Map.put(actor_guid, %{former | rank: 1})
        |> Map.put(target_guid, %{target | rank: 0})

      updated(guilds, %{group | leader: target_guid, members: members})
    else
      nil -> {:error, :target_not_in_guild}
      _ -> {:error, :permissions}
    end
  end

  def promote(%__MODULE__{} = guilds, actor_guid, target_guid), do: change_rank(guilds, actor_guid, target_guid, -1)
  def demote(%__MODULE__{} = guilds, actor_guid, target_guid), do: change_rank(guilds, actor_guid, target_guid, 1)

  defp change_rank(guilds, actor_guid, target_guid, direction) do
    group = group_of(guilds, actor_guid)
    permission = if(direction < 0, do: :promote, else: :demote)

    cond do
      group == nil ->
        {:error, :not_in_guild}

      not right?(group, actor_guid, permission) ->
        {:error, :permissions}

      member(group, target_guid) == nil ->
        {:error, :target_not_in_guild}

      member(group, target_guid).rank <= member(group, actor_guid).rank ->
        {:error, :rank_too_high}

      member(group, target_guid).rank + direction <= member(group, actor_guid).rank ->
        {:error, :rank_too_high}

      member(group, target_guid).rank + direction >= length(group.ranks) ->
        {:error, :rank_too_low}

      true ->
        target = member(group, target_guid)
        group = %{group | members: Map.put(group.members, target_guid, %{target | rank: target.rank + direction})}
        updated(guilds, group)
    end
  end

  def set_motd(%__MODULE__{} = guilds, actor_guid, motd) when is_binary(motd) do
    update_text(guilds, actor_guid, :set_motd, :motd, motd)
  end

  def set_info(%__MODULE__{} = guilds, actor_guid, info) when is_binary(info) do
    update_text(guilds, actor_guid, :edit_info, :info, info)
  end

  def set_emblem(%__MODULE__{} = guilds, actor_guid, {style, color, border, border_color, background} = emblem)
      when is_integer(style) and is_integer(color) and is_integer(border) and is_integer(border_color) and
             is_integer(background) do
    case group_of(guilds, actor_guid) do
      nil ->
        {:error, :not_in_guild}

      %Group{leader: leader} when leader != actor_guid ->
        {:error, :permissions}

      %Group{} = group ->
        if Enum.all?(Tuple.to_list(emblem), &(&1 in 0..255)) do
          updated(guilds, %{group | emblem: emblem})
        else
          {:error, :invalid_emblem}
        end
    end
  end

  def set_emblem(%__MODULE__{}, _actor_guid, _emblem), do: {:error, :invalid_emblem}

  defp update_text(guilds, actor_guid, permission, field, value) do
    case group_of(guilds, actor_guid) do
      nil ->
        {:error, :not_in_guild}

      group ->
        if right?(group, actor_guid, permission) do
          updated(guilds, %{group | field => value})
        else
          {:error, :permissions}
        end
    end
  end

  def set_note(%__MODULE__{} = guilds, actor_guid, target_guid, kind, note)
      when kind in [:public_note, :officer_note] and is_binary(note) do
    group = group_of(guilds, actor_guid)
    permission = if(kind == :public_note, do: :edit_public_note, else: :edit_officer_note)

    cond do
      group == nil ->
        {:error, :not_in_guild}

      not right?(group, actor_guid, permission) ->
        {:error, :permissions}

      member(group, target_guid) == nil ->
        {:error, :target_not_in_guild}

      true ->
        target = member(group, target_guid)
        group = %{group | members: Map.put(group.members, target_guid, %{target | kind => note})}
        updated(guilds, group)
    end
  end

  def edit_rank(%__MODULE__{} = guilds, actor_guid, rank_id, rights, name)
      when is_integer(rank_id) and is_integer(rights) and is_binary(name) do
    group = group_of(guilds, actor_guid)

    cond do
      group == nil ->
        {:error, :not_in_guild}

      group.leader != actor_guid ->
        {:error, :permissions}

      rank_out_of_bounds?(group, rank_id) ->
        {:error, :rank_too_low}

      invalid_rank_name?(name) ->
        {:error, :invalid_name}

      true ->
        update_rank(guilds, group, rank_id, rights, name)
    end
  end

  defp rank_out_of_bounds?(group, rank_id), do: rank_id < 0 or rank_id >= length(group.ranks)

  defp update_rank(guilds, group, rank_id, rights, name) do
    rank = Enum.at(group.ranks, rank_id)
    rights = if(rank_id == 0, do: @all_rights, else: Bitwise.band(rights, @all_rights) ||| 0x40)
    group = %{group | ranks: List.replace_at(group.ranks, rank_id, %{rank | name: name, rights: rights})}
    updated(guilds, group)
  end

  def add_rank(%__MODULE__{} = guilds, actor_guid, name) when is_binary(name) do
    group = group_of(guilds, actor_guid)

    cond do
      group == nil ->
        {:error, :not_in_guild}

      group.leader != actor_guid ->
        {:error, :permissions}

      length(group.ranks) >= 10 ->
        {:error, :rank_too_high}

      invalid_rank_name?(name) ->
        {:error, :invalid_name}

      true ->
        updated(guilds, %{
          group
          | ranks: group.ranks ++ [%Rank{name: name, rights: @right_guild_listen ||| @right_guild_speak}]
        })
    end
  end

  def delete_rank(%__MODULE__{} = guilds, actor_guid) do
    group = group_of(guilds, actor_guid)

    cond do
      group == nil ->
        {:error, :not_in_guild}

      group.leader != actor_guid ->
        {:error, :permissions}

      length(group.ranks) <= 5 ->
        {:error, :rank_too_low}

      true ->
        old_lowest = length(group.ranks) - 1
        members = removed_rank_members(group.members, old_lowest)
        updated(guilds, %{group | ranks: Enum.drop(group.ranks, -1), members: members})
    end
  end

  defp removed_rank_members(members, old_lowest) do
    Map.new(members, fn {guid, member} ->
      rank = if(member.rank == old_lowest, do: old_lowest - 1, else: member.rank)
      {guid, %{member | rank: rank}}
    end)
  end

  defp updated(guilds, group), do: {:ok, group, %{guilds | groups: Map.put(guilds.groups, group.id, group)}}

  def valid_name?(name) when is_binary(name) do
    String.length(name) >= 2 and String.length(name) <= @max_name_length and
      not String.match?(name, ~r/[[:cntrl:]]/) and not String.contains?(name, "  ")
  end

  defp invalid_rank_name?(name) do
    String.length(name) < 1 or String.length(name) > @max_rank_name_length or String.match?(name, ~r/[[:cntrl:]]/)
  end

  defp default_ranks do
    [
      %Rank{name: "Guild Master", rights: @all_rights},
      %Rank{name: "Officer", rights: @all_rights},
      %Rank{name: "Veteran", rights: @right_guild_listen ||| @right_guild_speak},
      %Rank{name: "Member", rights: @right_guild_listen ||| @right_guild_speak},
      %Rank{name: "Initiate", rights: @right_guild_listen ||| @right_guild_speak}
    ]
  end
end
