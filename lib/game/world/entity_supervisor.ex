defmodule ThistleTea.Game.World.EntitySupervisor do
  @moduledoc """
  Partitions non-player entity ownership so unrelated child starts can proceed concurrently.
  """

  @default_partitions 8

  def child_spec(opts) do
    partitions = Keyword.get(opts, :partitions, @default_partitions)

    PartitionSupervisor.child_spec(
      name: __MODULE__,
      partitions: partitions,
      child_spec: {DynamicSupervisor, strategy: :one_for_one, max_restarts: 1_000_000, max_seconds: 1}
    )
  end

  def start_child(partition_key, child_spec) do
    DynamicSupervisor.start_child(via(partition_key), child_spec)
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
