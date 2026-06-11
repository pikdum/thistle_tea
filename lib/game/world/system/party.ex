defmodule ThistleTea.Game.World.System.Party do
  @moduledoc """
  Boundary for the party system: serializes group mutations through one
  GenServer over the pure `ThistleTea.Game.Party` core and mirrors membership
  into a public ETS table for cheap concurrent reads.
  """
  use GenServer

  alias ThistleTea.Game.Party

  @table_options [:named_table, :public, read_concurrency: true]

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

  def group_of(guid) when is_integer(guid) do
    with [{^guid, group_id}] <- :ets.lookup(__MODULE__, guid),
         [{_key, group}] <- :ets.lookup(__MODULE__, {:group, group_id}) do
      group
    else
      _ -> nil
    end
  end

  def group_of(_guid), do: nil

  @impl GenServer
  def init(nil) do
    :ets.new(__MODULE__, @table_options)
    {:ok, %Party{}}
  end

  @impl GenServer
  def handle_call({:invite, inviter_guid, inviter_name, invitee_guid}, _from, party) do
    case Party.invite(party, inviter_guid, inviter_name, invitee_guid) do
      {:ok, party} -> {:reply, :ok, party}
      {:error, reason} -> {:reply, {:error, reason}, party}
    end
  end

  def handle_call({:accept, guid, name}, _from, party) do
    case Party.accept(party, guid, name) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  def handle_call({:decline, guid}, _from, party) do
    case Party.decline(party, guid) do
      {:ok, inviter, party} -> {:reply, {:ok, inviter}, party}
      {:error, reason} -> {:reply, {:error, reason}, party}
    end
  end

  def handle_call({:leave, guid}, _from, party) do
    case Party.leave(party, guid) do
      {:ok, outcome, party} ->
        index_removal(outcome, guid)
        {:reply, {:ok, outcome}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  def handle_call({:uninvite, remover_guid, target_guid}, _from, party) do
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

  def handle_call({:set_leader, requester_guid, new_leader_guid}, _from, party) do
    case Party.set_leader(party, requester_guid, new_leader_guid) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  def handle_call({:set_loot, requester_guid, method, master_looter, threshold}, _from, party) do
    case Party.set_loot(party, requester_guid, method, master_looter, threshold) do
      {:ok, group, party} ->
        index_group(group)
        {:reply, {:ok, group}, party}

      {:error, reason} ->
        {:reply, {:error, reason}, party}
    end
  end

  defp index_group(group) do
    :ets.insert(__MODULE__, {{:group, group.id}, group})
    Enum.each(group.members, fn member -> :ets.insert(__MODULE__, {member.guid, group.id}) end)
  end

  defp index_removal({:disbanded, group}, _removed_guid) do
    :ets.delete(__MODULE__, {:group, group.id})
    Enum.each(group.members, fn member -> :ets.delete(__MODULE__, member.guid) end)
  end

  defp index_removal({:removed, group, _leader_changed?}, removed_guid) do
    :ets.delete(__MODULE__, removed_guid)
    index_group(group)
  end
end
