defmodule ThistleTea.Auth.SessionKey do
  @moduledoc """
  Session keys negotiated by the logon server's SRP6 exchange, keyed by
  username, and the world server's `CMSG_AUTH_SESSION` proof check against
  them.
  """

  @table :session

  def init do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: :auto])
      _table -> @table
    end
  end

  def put(username, session_key) do
    :ets.insert(@table, {username, session_key})
    :ok
  end

  def fetch(username) do
    case :ets.lookup(@table, username) do
      [{^username, session_key}] -> {:ok, session_key}
      _missing -> :error
    end
  end

  def verify_world_proof(username, client_seed, server_seed, client_proof) do
    with {:ok, session_key} <- fetch(username),
         true <- world_proof(username, client_seed, server_seed, session_key) == client_proof do
      {:ok, session_key}
    else
      _invalid -> :error
    end
  end

  def world_proof(username, client_seed, server_seed, session_key) do
    :crypto.hash(:sha, username <> <<0::little-size(32)>> <> client_seed <> server_seed <> session_key)
  end
end
