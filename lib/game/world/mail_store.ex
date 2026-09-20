defmodule ThistleTea.Game.World.MailStore do
  @moduledoc """
  Application-owned mailbox custody and idempotent posting records. These
  runtime records survive Post Office restarts and disappear on server restart.
  """

  def init, do: :ets.new(__MODULE__, [:named_table, :public])

  def load(table) do
    case :ets.lookup(table, :mail) do
      [{:mail, state}] -> state
      [] -> %{next_id: 1, mailboxes: %{}, online: %{}, posted: %{}}
    end
  end

  def save(state, table) do
    true = :ets.insert(table, {:mail, state})
    :ok
  end
end
