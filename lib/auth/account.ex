defmodule ThistleTea.Account do
  @moduledoc """
  ETS store of game accounts by upcased username — in-memory only, like
  `CharacterStore`; durable persistence is deferred until the runtime model
  settles.
  """
  alias ThistleTea.Auth.SRP

  defstruct [:id, :username, :password_hash, :password_salt, :password_verifier]

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    table =
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, @table_options)
        _table_id -> table
      end

    :ets.insert_new(table, {:counter, 0})
    table
  end

  def register(username, password) do
    username = String.upcase(username)

    case user_exists?(username) do
      true -> {:error, "User already exists"}
      false -> create_account(username, password)
    end
  end

  def get_user(username) do
    username = String.upcase(username)

    case :ets.lookup(__MODULE__, username) do
      [{^username, %__MODULE__{} = account}] -> {:ok, account}
      _ -> {:error, "User not found"}
    end
  end

  defp user_exists?(username) do
    match?({:ok, _account}, get_user(username))
  end

  defp create_account(username, password) do
    salt = :crypto.strong_rand_bytes(32)

    account = %__MODULE__{
      id: next_id(),
      username: username,
      # TODO: use something better than sha256 here
      password_hash: :crypto.hash(:sha256, password),
      password_salt: salt,
      password_verifier: SRP.verifier(username, password, salt)
    }

    :ets.insert(__MODULE__, {username, account})
    {:ok, account}
  end

  defp next_id do
    :ets.update_counter(__MODULE__, :counter, 1)
  end
end
