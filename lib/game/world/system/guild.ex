defmodule ThistleTea.Game.World.System.Guild do
  @moduledoc """
  Serializes guild changes over the pure guild model. Membership survives
  logout and remains in memory until the server restarts.
  """
  use GenServer

  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Member

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %Guild{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def create(%Member{} = founder, name), do: change(:create, [founder, name, Date.utc_today()])

  def create_from_petition(%Member{} = founder, signers, name),
    do: change(:create_from_petition, [founder, signers, name, Date.utc_today()])

  def invite(inviter_guid, %Member{} = invitee), do: change(:invite, [inviter_guid, invitee])
  def accept(%Member{} = invitee), do: change(:accept, [invitee])
  def decline(guid), do: change(:decline, [guid])
  def leave(guid), do: change(:leave, [guid])
  def remove(actor_guid, target_guid), do: change(:remove, [actor_guid, target_guid])
  def disband(actor_guid), do: change(:disband, [actor_guid])
  def set_leader(actor_guid, target_guid), do: change(:set_leader, [actor_guid, target_guid])
  def promote(actor_guid, target_guid), do: change(:promote, [actor_guid, target_guid])
  def demote(actor_guid, target_guid), do: change(:demote, [actor_guid, target_guid])
  def set_motd(actor_guid, motd), do: change(:set_motd, [actor_guid, motd])
  def set_info(actor_guid, info), do: change(:set_info, [actor_guid, info])
  def set_emblem(actor_guid, emblem), do: change(:set_emblem, [actor_guid, emblem])
  def set_note(actor_guid, target_guid, kind, note), do: change(:set_note, [actor_guid, target_guid, kind, note])
  def edit_rank(actor_guid, rank_id, rights, name), do: change(:edit_rank, [actor_guid, rank_id, rights, name])
  def add_rank(actor_guid, name), do: change(:add_rank, [actor_guid, name])
  def delete_rank(actor_guid), do: change(:delete_rank, [actor_guid])

  def group_of(guid), do: GenServer.call(__MODULE__, {:group_of, guid})
  def invited?(guid), do: GenServer.call(__MODULE__, {:invited?, guid})
  def group(id), do: GenServer.call(__MODULE__, {:group, id})
  def group_by_name(name), do: GenServer.call(__MODULE__, {:group_by_name, name})

  defp change(action, args), do: GenServer.call(__MODULE__, {:change, action, args})

  @impl GenServer
  def init(guilds), do: {:ok, guilds}

  @impl GenServer
  def handle_call({:group_of, guid}, _from, guilds), do: {:reply, Guild.group_of(guilds, guid), guilds}
  def handle_call({:invited?, guid}, _from, guilds), do: {:reply, Guild.invited?(guilds, guid), guilds}
  def handle_call({:group, id}, _from, guilds), do: {:reply, Map.get(guilds.groups, id), guilds}
  def handle_call({:group_by_name, name}, _from, guilds), do: {:reply, Guild.group_by_name(guilds, name), guilds}

  def handle_call({:change, action, args}, _from, guilds) do
    case apply(Guild, action, [guilds | args]) do
      {:ok, result, updated} -> {:reply, {:ok, result}, updated}
      {:error, reason} -> {:reply, {:error, reason}, guilds}
    end
  rescue
    error ->
      Logger.error("guild change crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :internal}, guilds}
  end
end
