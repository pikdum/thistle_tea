defmodule ThistleTea.Game.World.AccountDataStore do
  @moduledoc """
  Account-wide client data shared by all of an account's characters, such as
  seen tutorials. In-memory only, like `CharacterStore`.
  """

  alias ThistleTea.Game.Core.Player.Tutorials

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def tutorials(account_id) when is_integer(account_id) do
    case :ets.lookup(__MODULE__, {:tutorials, account_id}) do
      [{_key, flags}] -> flags
      [] -> Tutorials.new()
    end
  end

  def tutorials(_account_id), do: Tutorials.new()

  def put_tutorials(account_id, flags) when is_integer(account_id) and is_list(flags) do
    :ets.insert(__MODULE__, {{:tutorials, account_id}, flags})
    flags
  end
end
