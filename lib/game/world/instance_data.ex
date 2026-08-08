defmodule ThistleTea.Game.World.InstanceData do
  @moduledoc """
  Concurrent read projection of authoritative per-copy instance script data.
  """

  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.InstanceScript
  alias ThistleTea.Game.WorldRef

  defmodule Snapshot do
    @moduledoc false
    @enforce_keys [:world, :status]
    defstruct [:world, :status, :script_name, fields: %{}]
  end

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def publish(table \\ __MODULE__, %Copy{} = copy) do
    true = :ets.insert(table, {copy.world, copy.script_name, copy.data})
    :ok
  end

  def remove(table \\ __MODULE__, %WorldRef{} = world) do
    true = :ets.delete(table, world)
    :ok
  end

  def read(world, fields, table \\ __MODULE__)

  def read(%WorldRef{instance_id: nil} = world, _fields, _table) do
    %Snapshot{world: world, status: :open_world}
  end

  def read(%WorldRef{} = world, fields, table) do
    case :ets.lookup(table, world) do
      [{^world, script_name, data}] -> snapshot(world, script_name, data, fields)
      [] -> %Snapshot{world: world, status: :missing_copy}
    end
  end

  def read(world, _fields, _table), do: %Snapshot{world: world, status: :open_world}

  def read_all(world, table \\ __MODULE__)

  def read_all(%WorldRef{instance_id: nil} = world, _table) do
    %Snapshot{world: world, status: :open_world}
  end

  def read_all(%WorldRef{} = world, table) do
    case :ets.lookup(table, world) do
      [{^world, script_name, _data}] -> read(world, InstanceScript.registered_fields(script_name), table)
      [] -> %Snapshot{world: world, status: :missing_copy}
    end
  end

  def read_all(world, _table), do: %Snapshot{world: world, status: :open_world}

  defp snapshot(world, nil, _data, _fields) do
    %Snapshot{world: world, status: :no_instance_script}
  end

  defp snapshot(world, script_name, data, fields) do
    case InstanceScript.registered_fields(script_name) do
      [] ->
        %Snapshot{world: world, status: {:unsupported_script, script_name}, script_name: script_name}

      _registered ->
        values =
          fields
          |> Enum.uniq()
          |> Map.new(fn field -> {field, projected_value(script_name, data, field)} end)

        %Snapshot{world: world, status: :available, script_name: script_name, fields: values}
    end
  end

  defp projected_value(script_name, data, field) do
    with {:ok, initial} <- InstanceScript.initial_value(script_name, field) do
      {:ok, Map.get(data, field, initial)}
    end
  end
end
