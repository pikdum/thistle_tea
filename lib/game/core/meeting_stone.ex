defmodule ThistleTea.Game.Core.MeetingStone do
  @moduledoc "Pure Meeting Stone queues, class-role matching, and party lifecycle notifications."

  alias ThistleTea.Game.Core.MeetingStone.Roles
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Party.Group
  alias ThistleTea.Game.Core.Party.Member

  defmodule Applicant do
    @moduledoc false
    defstruct [:guid, :name, :class, :team, online?: false]
  end

  defmodule Ticket do
    @moduledoc false
    defstruct [:area, :team, :leader, :queued_at, :progress_at, members: []]
  end

  defstruct solos: %{}, groups: %{}

  @progress_ms 300_000
  @priority_ms 1_800_000

  def join(%__MODULE__{} = queue, %Party{} = party, %Applicant{} = actor, area, now)
      when is_integer(area) and area > 0 and is_integer(now) do
    group = Party.group_of(party, actor.guid)

    with :ok <- eligible(group, actor.guid),
         true <- actor.online? and actor.team in [:alliance, :horde] do
      ticket = %Ticket{area: area, team: actor.team, queued_at: now, progress_at: now + @progress_ms}

      case group do
        nil ->
          ticket = %{ticket | members: [actor.guid]}
          {:ok, %{queue | solos: Map.put(queue.solos, actor.guid, ticket)}, status_events(ticket, 1)}

        %Group{} ->
          ticket = %{ticket | leader: group.leader, members: guids(group)}

          queue = %{
            queue
            | groups: Map.put(queue.groups, group.id, ticket),
              solos: Map.drop(queue.solos, ticket.members)
          }

          {:ok, queue, status_events(ticket, 1)}
      end
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  def join(%__MODULE__{}, %Party{}, %Applicant{}, _area, _now), do: {:error, :unavailable}

  def leave(%__MODULE__{} = queue, %Party{} = party, guid) do
    case Party.group_of(party, guid) do
      %Group{leader: ^guid, id: id} ->
        case Map.pop(queue.groups, id) do
          {nil, _groups} -> {queue, [{:status, [guid], 0, 5}]}
          {ticket, groups} -> {%{queue | groups: groups}, [{:status, ticket.members, 0, 0}]}
        end

      %Group{} ->
        {queue, [{:status, [guid], 0, 5}]}

      nil ->
        {%{queue | solos: Map.delete(queue.solos, guid)}, [{:status, [guid], 0, 0}]}
    end
  end

  def status(%__MODULE__{} = queue, %Party{} = party, guid) do
    ticket =
      case Party.group_of(party, guid) do
        %Group{id: id} -> queue.groups[id]
        nil -> queue.solos[guid]
      end

    if ticket, do: {:status, [guid], ticket.area, 1}, else: {:status, [guid], 0, 5}
  end

  def candidates(%__MODULE__{} = queue) do
    (Map.values(queue.solos) ++ Map.values(queue.groups)) |> Enum.flat_map(& &1.members) |> Enum.uniq()
  end

  def party_changed(queue, previous, party, {:uninvite, _remover, guid}, now) do
    with %Group{} = group <- Party.group_of(previous, guid),
         %Ticket{} = ticket <- queue.groups[group.id],
         %Group{} = remaining <- party.groups[group.id],
         nil <- Party.member(remaining, guid) do
      solo = %{ticket | leader: nil, members: [guid], queued_at: now, progress_at: now + @progress_ms}
      queue = %{queue | groups: Map.delete(queue.groups, group.id), solos: Map.put(queue.solos, guid, solo)}
      {queue, [{:status, guids(remaining), 0, 3}, {:status, [guid], ticket.area, 4}]}
    else
      _ -> {queue, []}
    end
  end

  def party_changed(queue, _previous, _party, _request, _now), do: {queue, []}

  def refresh(%__MODULE__{} = queue, %Party{} = party, players, now) do
    {queue, events} = synchronize(queue, party, now)
    {queue, party, events} = fill_groups(queue, party, players, now, events)
    form_groups(queue, party, players, now, events)
  end

  defp eligible(%Group{leader: leader}, guid) when leader != guid, do: {:error, :not_leader}
  defp eligible(%Group{raid?: true}, _guid), do: {:error, :raid_group}
  defp eligible(%Group{members: members}, _guid) when length(members) >= 5, do: {:error, :full_group}
  defp eligible(_group, _guid), do: :ok

  def synchronize(%__MODULE__{} = queue, %Party{} = party, now) do
    {solos, solo_events} =
      Enum.reduce(queue.solos, {%{}, []}, fn {guid, ticket}, {solos, events} ->
        if Party.in_group?(party, guid) do
          {solos, events ++ [{:status, [guid], 0, 5}]}
        else
          {Map.put(solos, guid, ticket), events}
        end
      end)

    {groups, events} =
      Enum.reduce(Enum.sort(queue.groups), {%{}, solo_events}, fn {id, ticket}, {groups, events} ->
        synchronize_group(party.groups[id], ticket, now, groups, events)
      end)

    {%{queue | solos: solos, groups: groups}, events}
  end

  defp synchronize_group(%Group{raid?: false, members: members} = group, ticket, now, groups, events)
       when length(members) < 5 do
    current = guids(group)

    if ticket.leader in current do
      changes = membership_events(ticket, current)
      progress = if now >= ticket.progress_at, do: [{:progress, current}], else: []
      deadline = if progress == [], do: ticket.progress_at, else: now + @progress_ms
      ticket = %{ticket | leader: group.leader, members: current, progress_at: deadline}
      {Map.put(groups, group.id, ticket), events ++ changes ++ progress}
    else
      {groups, events ++ [{:status, ticket.members, 0, 0}]}
    end
  end

  defp synchronize_group(%Group{raid?: false} = group, ticket, _now, groups, events),
    do: {groups, events ++ membership_events(ticket, guids(group)) ++ completed(group)}

  defp synchronize_group(_group, ticket, _now, groups, events),
    do: {groups, events ++ [{:status, ticket.members, 0, 0}]}

  defp membership_events(ticket, current) do
    removed = ticket.members -- current
    added = current -- ticket.members
    removed_events = if removed == [], do: [], else: [{:status, removed, 0, 5}, {:status, current, ticket.area, 2}]
    added_events = if added == [], do: [], else: [{:status, added, ticket.area, 1}]
    removed_events ++ added_events
  end

  defp fill_groups(queue, party, players, now, events) do
    Enum.reduce(Enum.sort(queue.groups), {queue, party, events}, fn {id, _ticket}, {queue, party, events} ->
      fill_group(queue, party, id, players, now, events)
    end)
  end

  defp fill_group(queue, party, id, players, now, events) do
    group = party.groups[id]
    ticket = queue.groups[id]

    candidate =
      if online?(players[group.leader]) do
        group.members
        |> Enum.map(&Map.get(players, &1.guid, %Applicant{}))
        |> Roles.available()
        |> Enum.find_value(&candidate(queue, party, ticket, players, &1, now))
      end

    case candidate do
      %Applicant{} = actor ->
        member = %Member{guid: actor.guid, name: actor.name}
        {:ok, group, party} = Party.matchmake(party, group.leader, member, group.id)
        ticket = %{ticket | members: guids(group)}
        queue = %{queue | solos: Map.delete(queue.solos, actor.guid), groups: Map.put(queue.groups, id, ticket)}

        events =
          events ++ [{:member, ticket.members, actor.guid}, {:group, group}, {:status, [actor.guid], ticket.area, 1}]

        if length(group.members) == 5 do
          {%{queue | groups: Map.delete(queue.groups, id)}, party, events ++ completed(group)}
        else
          fill_group(queue, party, id, players, now, events)
        end

      nil ->
        {queue, party, events}
    end
  end

  defp candidate(queue, party, ticket, players, role, now) do
    queue.solos
    |> Enum.filter(fn {guid, entry} ->
      actor = players[guid]

      entry.area == ticket.area and entry.team == ticket.team and available?(party, actor) and
        Roles.priority(actor.class, role) > 0
    end)
    |> Enum.min_by(
      fn {guid, entry} ->
        {if(now - entry.queued_at >= @priority_ms, do: 0, else: 1), -Roles.priority(players[guid].class, role),
         entry.queued_at, guid}
      end,
      fn -> nil end
    )
    |> case do
      {guid, _ticket} -> players[guid]
      nil -> nil
    end
  end

  defp form_groups(queue, party, players, now, events) do
    cohort =
      queue.solos
      |> Enum.filter(fn {guid, _ticket} -> available?(party, players[guid]) end)
      |> Enum.group_by(fn {_guid, ticket} -> {ticket.area, ticket.team} end)
      |> Enum.sort()
      |> Enum.find_value(&cohort_members/1)

    case cohort do
      [{leader, ticket}, {guid, _} | _] ->
        {:ok, party} = Party.invite(party, leader, players[leader].name, guid)
        {:ok, group, party} = Party.accept(party, guid, players[guid].name)
        ticket = %{ticket | leader: group.leader, members: guids(group), progress_at: now + @progress_ms}
        queue = %{queue | solos: Map.drop(queue.solos, [leader, guid]), groups: Map.put(queue.groups, group.id, ticket)}
        events = events ++ [{:member, ticket.members, guid}, {:group, group}] ++ status_events(ticket, 1)
        {queue, party, events} = fill_group(queue, party, group.id, players, now, events)
        form_groups(queue, party, players, now, events)

      nil ->
        {queue, party, events}
    end
  end

  defp cohort_members({_key, entries}) when length(entries) >= 5,
    do: Enum.sort_by(entries, fn {guid, ticket} -> {ticket.queued_at, guid} end)

  defp cohort_members(_cohort), do: nil

  defp available?(party, %Applicant{online?: true, guid: guid}),
    do: not Party.in_group?(party, guid) and not Party.invited?(party, guid)

  defp available?(_party, _actor), do: false
  defp online?(%Applicant{online?: true}), do: true
  defp online?(_actor), do: false
  defp completed(group), do: [{:complete, guids(group)}, {:status, guids(group), 0, 5}]
  defp status_events(ticket, status), do: [{:status, ticket.members, ticket.area, status}]
  defp guids(group), do: Enum.map(group.members, & &1.guid)
end
