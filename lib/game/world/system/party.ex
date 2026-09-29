defmodule ThistleTea.Game.World.System.Party do
  @moduledoc """
  Boundary for the party system: serializes group mutations through one
  GenServer over the pure `ThistleTea.Game.Core.Party` core and mirrors membership
  into a public ETS table for cheap concurrent reads.
  """
  use GenServer

  alias ThistleTea.Game.Core.MeetingStone
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party.MeetingStones
  alias ThistleTea.Game.World.System.Party.Notifier

  require Logger

  @table_options [:named_table, :public, read_concurrency: true]

  defmodule State do
    @moduledoc false
    defstruct party: %Party{}, queue: %MeetingStone{}
  end

  def meeting_stone(action, guid, area \\ nil), do: GenServer.call(__MODULE__, {:meeting_stone, action, guid, area})

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, Keyword.put_new(opts, :name, __MODULE__))
  end

  def invite(inviter_guid, inviter_name, invitee_guid) do
    GenServer.call(__MODULE__, {:invite, inviter_guid, inviter_name, invitee_guid})
  end

  def accept(guid, name), do: GenServer.call(__MODULE__, {:accept, guid, name})

  def decline(guid), do: GenServer.call(__MODULE__, {:decline, guid})

  def leave(guid), do: GenServer.call(__MODULE__, {:leave, guid})

  def uninvite(remover_guid, target_guid) do
    GenServer.call(__MODULE__, {:uninvite, remover_guid, target_guid})
  end

  def set_leader(requester_guid, new_leader_guid) do
    GenServer.call(__MODULE__, {:set_leader, requester_guid, new_leader_guid})
  end

  def set_loot(requester_guid, method, master_looter, threshold) do
    GenServer.call(__MODULE__, {:set_loot, requester_guid, method, master_looter, threshold})
  end

  def convert_raid(guid), do: raid_action(:convert_raid, [guid])
  def set_assistant(guid, target, enabled?), do: raid_action(:set_assistant, [guid, target, enabled?])
  def change_subgroup(guid, target, subgroup), do: raid_action(:change_subgroup, [guid, target, subgroup])
  def swap_subgroups(guid, first, second), do: raid_action(:swap_subgroups, [guid, first, second])
  def set_icon(guid, icon, target), do: GenServer.call(__MODULE__, {:set_icon, guid, icon, target})

  defp raid_action(action, arguments), do: GenServer.call(__MODULE__, {:raid_action, action, arguments})

  def update_looter(group_id, eligible_guids) do
    GenServer.call(__MODULE__, {:update_looter, group_id, eligible_guids})
  end

  def group_of(guid) when is_integer(guid) do
    with [{^guid, group_id}] <- :ets.lookup(__MODULE__, guid),
         [{_key, group}] <- :ets.lookup(__MODULE__, {:group, group_id}) do
      group
    else
      _ -> nil
    end
  end

  def group_of(_guid), do: nil

  def group(id) when is_integer(id) do
    case :ets.lookup(__MODULE__, {:group, id}) do
      [{_key, group}] -> group
      _missing -> nil
    end
  end

  def group(_id), do: nil

  @impl GenServer
  def init(nil) do
    :ets.new(__MODULE__, @table_options)
    Process.send_after(self(), :meeting_stone_tick, 1_000)
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call({:meeting_stone, action, guid, area}, _from, %State{} = state) do
    {queue, events} = MeetingStones.request(state.queue, state.party, action, guid, area, Time.now())
    Enum.each(events, &deliver_queue_event/1)
    {:reply, :ok, refresh_queue(%{state | queue: queue})}
  rescue
    error ->
      Logger.error("Meeting Stone request failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :unavailable}, state}
  end

  def handle_call(request, from, %State{} = state) do
    {:reply, reply, party} = handle_party_call(request, from, state.party)
    {queue, events} = MeetingStone.party_changed(state.queue, state.party, party, request, Time.now())
    Enum.each(events, &deliver_queue_event/1)
    {:reply, reply, synchronize_queue(%{state | party: party, queue: queue})}
  rescue
    error ->
      Logger.error("Party request failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :unavailable}, state}
  end

  @impl GenServer
  def handle_info(:meeting_stone_tick, %State{} = state) do
    Process.send_after(self(), :meeting_stone_tick, 1_000)
    {:noreply, refresh_queue(state)}
  rescue
    error ->
      Logger.error("Meeting Stone matching failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  defp synchronize_queue(%State{} = state) do
    {queue, events} = MeetingStone.synchronize(state.queue, state.party, Time.now())
    Enum.each(events, &deliver_queue_event/1)
    %{state | queue: queue}
  end

  defp refresh_queue(%State{queue: %MeetingStone{solos: solos, groups: groups}} = state)
       when map_size(solos) == 0 and map_size(groups) == 0, do: state

  defp refresh_queue(%State{} = state) do
    {queue, party, events} = MeetingStones.refresh(state.queue, state.party, Time.now())
    Enum.each(events, &deliver_queue_event/1)
    %{state | queue: queue, party: party}
  end

  defp deliver_queue_event({:group, group}) do
    index_group(group)
    Notifier.send_group_list(group)
  end

  defp deliver_queue_event(event), do: MeetingStones.deliver(event)

  defp handle_party_call({:invite, inviter_guid, inviter_name, invitee_guid}, _from, party) do
    case Party.invite(party, inviter_guid, inviter_name, invitee_guid) do
      {:ok, party} -> {:reply, :ok, party}
      {:error, reason} -> {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:accept, guid, name}, _from, party) do
    case Party.accept(party, guid, name) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:decline, guid}, _from, party) do
    case Party.decline(party, guid) do
      {:ok, inviter, party} -> {:reply, {:ok, inviter}, party}
      {:error, reason} -> {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:leave, guid}, _from, party) do
    case Party.leave(party, guid) do
      {:ok, outcome, party} ->
        index_removal(outcome, guid)
        {:reply, {:ok, outcome}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:uninvite, remover_guid, target_guid}, _from, party) do
    case Party.uninvite(party, remover_guid, target_guid) do
      {:ok, :invite_cancelled, party} ->
        {:reply, {:ok, :invite_cancelled}, party}

      {:ok, outcome, party} ->
        index_removal(outcome, target_guid)
        {:reply, {:ok, outcome}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:set_leader, requester_guid, new_leader_guid}, _from, party) do
    case Party.set_leader(party, requester_guid, new_leader_guid) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:update_looter, group_id, eligible_guids}, _from, party) do
    {looter, party} = Party.update_looter(party, group_id, eligible_guids)

    case Map.get(party.groups, group_id) do
      %Party.Group{} = group -> index_group(group)
      _ -> :ok
    end

    {:reply, looter, party}
  end

  defp handle_party_call({:set_loot, requester_guid, method, master_looter, threshold}, _from, party) do
    case Party.set_loot(party, requester_guid, method, master_looter, threshold) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:raid_action, action, arguments}, _from, party)
       when action in [:convert_raid, :set_assistant, :change_subgroup, :swap_subgroups] do
    case apply(Party, action, [party | arguments]) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp handle_party_call({:set_icon, guid, icon, target}, _from, party) do
    case Party.set_icon(party, guid, icon, target) do
      {:ok, group, changes, party} ->
        index_group(group)
        {:reply, {:ok, group, changes}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp index_group(group) do
    previous = group(group.id)
    :ets.insert(__MODULE__, {{:group, group.id}, group})
    Enum.each(group.members, fn member -> :ets.insert(__MODULE__, {member.guid, group.id}) end)

    if membership(previous) != membership(group), do: InstanceSystem.group_changed(previous, group)
  end

  defp index_removal({:disbanded, group}, _removed_guid) do
    :ets.delete(__MODULE__, {:group, group.id})
    Enum.each(group.members, fn member -> :ets.delete(__MODULE__, member.guid) end)
    InstanceSystem.group_changed(group, nil)
  end

  defp index_removal({:removed, group, _leader_changed?}, removed_guid) do
    :ets.delete(__MODULE__, removed_guid)
    index_group(group)
  end

  defp membership(%Party.Group{} = group), do: {group.leader, group.raid?, Enum.map(group.members, & &1.guid)}
  defp membership(nil), do: nil
end
