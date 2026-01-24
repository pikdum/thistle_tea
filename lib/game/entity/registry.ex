defmodule ThistleTea.Game.Entity.Registry do
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  def via(guid) when is_integer(guid) do
    {:via, Registry, {__MODULE__, guid}}
  end

  def register(guid) when is_integer(guid) do
    Registry.register(__MODULE__, guid, nil)
  end

  def register(_guid), do: {:error, :invalid_guid}

  def unregister(guid) when is_integer(guid) do
    Registry.unregister(__MODULE__, guid)
  end

  def unregister(_guid), do: :ok

  def whereis(guid) when is_integer(guid) do
    case Registry.lookup(__MODULE__, guid) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def whereis(_guid), do: nil

  def registered?(guid) when is_integer(guid) do
    case Registry.lookup(__MODULE__, guid) do
      [{pid, _}] when is_pid(pid) -> true
      _ -> false
    end
  end

  def registered?(_guid), do: false
end
