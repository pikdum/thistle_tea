defmodule ThistleTea.Game.Chat.Channel do
  @moduledoc """
  Pure chat-channel state and authorization: membership, ownership,
  moderation, passwords, bans, and speaking permissions.
  """
  import Bitwise

  defmodule Member do
    @moduledoc false
    defstruct [:guid, :name, :team, flags: 0]
  end

  defstruct [
    :key,
    :name,
    :team,
    :kind,
    :owner_guid,
    flags: 0,
    password: "",
    announcements?: false,
    moderated?: false,
    members: %{},
    banned: MapSet.new()
  ]

  @custom_flag 0x01
  @owner_flag 0x01
  @moderator_flag 0x02
  @muted_flag 0x08

  def custom_flag, do: @custom_flag
  def owner_flag, do: @owner_flag
  def moderator_flag, do: @moderator_flag
  def muted_flag, do: @muted_flag

  def new(key, name, team, %{kind: kind, flags: flags}) do
    %__MODULE__{
      key: key,
      name: name,
      team: team,
      kind: kind,
      flags: flags,
      announcements?: kind == :custom
    }
  end

  def join(%__MODULE__{} = channel, %Member{} = member, password) do
    cond do
      Map.has_key?(channel.members, member.guid) ->
        {:error, :already_member}

      MapSet.member?(channel.banned, member.guid) ->
        {:error, :banned}

      channel.password != "" and channel.password != password ->
        {:error, :wrong_password}

      true ->
        owner_assigned? = channel.kind == :custom and is_nil(channel.owner_guid)
        flags = if owner_assigned?, do: @owner_flag ||| @moderator_flag, else: 0
        member = %{member | flags: flags}
        recipients = Map.keys(channel.members)

        channel = %{
          channel
          | owner_guid: if(owner_assigned?, do: member.guid, else: channel.owner_guid),
            members: Map.put(channel.members, member.guid, member)
        }

        {:ok, channel, %{member: member, recipients: recipients, owner_assigned?: owner_assigned?}}
    end
  end

  def leave(%__MODULE__{} = channel, guid) do
    case Map.fetch(channel.members, guid) do
      :error ->
        {:error, :not_member}

      {:ok, member} ->
        owner_left? = channel.owner_guid == guid
        members = Map.delete(channel.members, guid)
        {owner_guid, members, owner_change} = transfer_owner(channel.owner_guid, members, owner_left?)
        channel = %{channel | owner_guid: owner_guid, members: members}

        {:ok, channel,
         %{member: member, recipients: Map.keys(members), owner_change: owner_change, empty?: map_size(members) == 0}}
    end
  end

  def speak(%__MODULE__{} = channel, guid) do
    case Map.fetch(channel.members, guid) do
      :error ->
        {:error, :not_member}

      {:ok, %Member{} = member} ->
        cond do
          flag?(member, @muted_flag) -> {:error, :muted}
          channel.moderated? and not moderator?(member) -> {:error, :not_moderator}
          true -> {:ok, Map.values(channel.members)}
        end
    end
  end

  def list(%__MODULE__{} = channel, guid) do
    if Map.has_key?(channel.members, guid) do
      {:ok, Map.values(channel.members)}
    else
      {:error, :not_member}
    end
  end

  def set_password(%__MODULE__{} = channel, actor_guid, password) do
    with {:ok, _actor} <- authorize_moderator(channel, actor_guid) do
      {:ok, %{channel | password: password}}
    end
  end

  def set_owner(%__MODULE__{} = channel, actor_guid, target_name) do
    with {:ok, _actor} <- authorize_owner(channel, actor_guid),
         {:ok, target} <- fetch_member_by_name(channel, target_name) do
      old_owner = Map.get(channel.members, channel.owner_guid)
      new_owner_old_flags = target.flags

      members =
        channel.members
        |> update_member_flags(old_owner, &band(&1, bnot(@owner_flag)))
        |> update_member_flags(target, &bor(&1, @owner_flag ||| @moderator_flag))

      target = Map.fetch!(members, target.guid)
      channel = %{channel | owner_guid: target.guid, members: members}
      {:ok, channel, %{old_owner: old_owner, new_owner: target, new_owner_old_flags: new_owner_old_flags}}
    end
  end

  def set_mode(%__MODULE__{} = channel, actor_guid, target_name, mode, enabled?)
      when mode in [:moderator, :muted] and is_boolean(enabled?) do
    with {:ok, actor} <- authorize_moderator(channel, actor_guid),
         {:ok, target} <- fetch_member_by_name(channel, target_name),
         :ok <- authorize_target(actor, target),
         :ok <- preserve_owner_moderation(target, mode, enabled?) do
      flag = mode_flag(mode)
      old_flags = target.flags
      flags = if enabled?, do: bor(old_flags, flag), else: band(old_flags, bnot(flag))
      target = %{target | flags: flags}
      channel = %{channel | members: Map.put(channel.members, target.guid, target)}
      {:ok, channel, %{member: target, old_flags: old_flags}}
    end
  end

  def kick(%__MODULE__{} = channel, actor_guid, target_name, ban?) when is_boolean(ban?) do
    with {:ok, actor} <- authorize_moderator(channel, actor_guid),
         {:ok, target} <- fetch_member_by_name(channel, target_name),
         :ok <- authorize_target(actor, target),
         {:ok, channel, outcome} <- leave(channel, target.guid) do
      banned = if ban?, do: MapSet.put(channel.banned, target.guid), else: channel.banned
      {:ok, %{channel | banned: banned}, Map.put(outcome, :target, target)}
    end
  end

  def unban(%__MODULE__{} = channel, actor_guid, target_guid, target_name) do
    with {:ok, _actor} <- authorize_moderator(channel, actor_guid) do
      if MapSet.member?(channel.banned, target_guid) do
        {:ok, %{channel | banned: MapSet.delete(channel.banned, target_guid)}}
      else
        {:error, {:not_banned, target_name}}
      end
    end
  end

  def invite(%__MODULE__{} = channel, actor_guid, %Member{} = target) do
    with {:ok, _actor} <- fetch_member(channel, actor_guid) do
      cond do
        target.team != channel.team -> {:error, :wrong_faction}
        Map.has_key?(channel.members, target.guid) -> {:error, {:already_member, target.guid}}
        MapSet.member?(channel.banned, target.guid) -> {:error, {:invite_banned, target.name}}
        true -> :ok
      end
    end
  end

  def toggle_announcements(%__MODULE__{} = channel, actor_guid) do
    with {:ok, _actor} <- authorize_moderator(channel, actor_guid) do
      {:ok, %{channel | announcements?: not channel.announcements?}}
    end
  end

  def toggle_moderation(%__MODULE__{} = channel, actor_guid) do
    with {:ok, _actor} <- authorize_moderator(channel, actor_guid) do
      {:ok, %{channel | moderated?: not channel.moderated?}}
    end
  end

  def fetch_member(%__MODULE__{} = channel, guid) do
    case Map.fetch(channel.members, guid) do
      {:ok, member} -> {:ok, member}
      :error -> {:error, :not_member}
    end
  end

  def fetch_member_by_name(%__MODULE__{} = channel, name) do
    normalized = normalize(name)

    case Enum.find(channel.members, fn {_guid, member} -> normalize(member.name) == normalized end) do
      {_guid, member} -> {:ok, member}
      nil -> {:error, {:player_not_found, name}}
    end
  end

  def moderator?(%Member{} = member), do: flag?(member, @moderator_flag)
  def owner?(%Member{} = member), do: flag?(member, @owner_flag)

  defp authorize_moderator(channel, guid) do
    with {:ok, member} <- fetch_member(channel, guid) do
      if moderator?(member), do: {:ok, member}, else: {:error, :not_moderator}
    end
  end

  defp authorize_owner(channel, guid) do
    with {:ok, member} <- fetch_member(channel, guid) do
      if owner?(member), do: {:ok, member}, else: {:error, :not_owner}
    end
  end

  defp authorize_target(actor, target) do
    if owner?(target) and not owner?(actor), do: {:error, :not_owner}, else: :ok
  end

  defp preserve_owner_moderation(target, :moderator, false) do
    if owner?(target), do: {:error, :not_owner}, else: :ok
  end

  defp preserve_owner_moderation(_target, _mode, _enabled?), do: :ok

  defp transfer_owner(owner_guid, members, false), do: {owner_guid, members, nil}

  defp transfer_owner(_owner_guid, members, true) when map_size(members) == 0, do: {nil, members, nil}

  defp transfer_owner(_owner_guid, members, true) do
    {guid, member} = Enum.min_by(members, fn {guid, _member} -> guid end)
    old_flags = member.flags
    member = %{member | flags: bor(member.flags, @owner_flag ||| @moderator_flag)}
    {guid, Map.put(members, guid, member), %{member: member, old_flags: old_flags}}
  end

  defp update_member_flags(members, nil, _fun), do: members

  defp update_member_flags(members, %Member{} = member, fun) do
    Map.put(members, member.guid, %{member | flags: fun.(member.flags)})
  end

  defp mode_flag(:moderator), do: @moderator_flag
  defp mode_flag(:muted), do: @muted_flag

  defp flag?(member, flag), do: band(member.flags, flag) != 0
  defp normalize(value), do: value |> String.trim() |> String.downcase()
end
