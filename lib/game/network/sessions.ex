defmodule ThistleTea.Game.Network.Sessions do
  @moduledoc """
  Authenticated world connections, including character selection. Registry
  ownership removes disconnected sessions without counting cached auth keys.
  """

  def child_spec(opts) do
    Registry.child_spec(keys: :unique, name: Keyword.get(opts, :name, __MODULE__))
  end

  def authenticate(account_id, registry \\ __MODULE__) when is_integer(account_id) do
    case Registry.register(registry, self(), account_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_registered, _pid}} -> Registry.update_value(registry, self(), fn _ -> account_id end)
    end

    :ok
  end

  def count(registry \\ __MODULE__) do
    registry
    |> Registry.select([{{:_, :_, :"$1"}, [], [:"$1"]}])
    |> Enum.uniq()
    |> length()
  end
end
