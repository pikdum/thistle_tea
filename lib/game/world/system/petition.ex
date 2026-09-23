defmodule ThistleTea.Game.World.System.Petition do
  @moduledoc """
  Serializes guild charter ownership and signatures in runtime memory.
  """
  use GenServer

  alias ThistleTea.Game.Guild.Member
  alias ThistleTea.Game.Guild.Petitions

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %Petitions{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def create(%Member{} = owner, account_id, item_guid, id, name),
    do: change(:create, [owner, account_id, item_guid, id, name])

  def sign(item_guid, %Member{} = signer, account_id), do: change(:sign, [item_guid, signer, account_id])
  def rename(item_guid, owner_guid, name), do: change(:rename, [item_guid, owner_guid, name])
  def delete(item_guid), do: change(:delete, [item_guid])
  def revoke_signer(guid), do: GenServer.call(__MODULE__, {:revoke_signer, guid})
  def by_item(item_guid), do: GenServer.call(__MODULE__, {:by_item, item_guid})
  def by_id(id), do: GenServer.call(__MODULE__, {:by_id, id})
  def by_owner(guid), do: GenServer.call(__MODULE__, {:by_owner, guid})

  defp change(action, args), do: GenServer.call(__MODULE__, {:change, action, args})

  @impl GenServer
  def init(petitions), do: {:ok, petitions}

  @impl GenServer
  def handle_call({:by_item, item_guid}, _from, state), do: {:reply, Petitions.by_item(state, item_guid), state}
  def handle_call({:by_id, id}, _from, state), do: {:reply, Petitions.by_id(state, id), state}
  def handle_call({:by_owner, guid}, _from, state), do: {:reply, Petitions.by_owner(state, guid), state}

  def handle_call({:revoke_signer, guid}, _from, state) do
    {:reply, :ok, Petitions.revoke_signer(state, guid)}
  end

  def handle_call({:change, action, args}, _from, state) do
    case apply(Petitions, action, [state | args]) do
      {:ok, result, updated} -> {:reply, {:ok, result}, updated}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  rescue
    error ->
      Logger.error("petition change crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :internal}, state}
  end
end
