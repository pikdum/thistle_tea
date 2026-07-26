defmodule ThistleTea.Game.World.SpawnPool.Supervisor do
  @moduledoc """
  Partitions spawn-pool owner startup while preserving stable routing by pool key.
  """

  @default_partitions 8

  def child_spec(opts) do
    partitions = Keyword.get(opts, :partitions, @default_partitions)

    PartitionSupervisor.child_spec(
      name: __MODULE__,
      partitions: partitions,
      child_spec: {DynamicSupervisor, strategy: :one_for_one}
    )
  end

  def start_child(partition_key, child_spec) do
    DynamicSupervisor.start_child(via(partition_key), child_spec)
  end

  def terminate_child(partition_key, pid) when is_pid(pid) do
    partition_key
    |> via()
    |> DynamicSupervisor.terminate_child(pid)
  end

  def terminate_child(pid) when is_pid(pid) do
    __MODULE__
    |> PartitionSupervisor.which_children()
    |> Enum.reduce_while({:error, :not_found}, fn {_id, supervisor, _type, _modules}, _acc ->
      case DynamicSupervisor.terminate_child(supervisor, pid) do
        :ok -> {:halt, :ok}
        {:error, :not_found} -> {:cont, {:error, :not_found}}
      end
    end)
  end

  defp via(partition_key), do: {:via, PartitionSupervisor, {__MODULE__, partition_key}}
end
