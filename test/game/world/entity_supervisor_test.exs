defmodule ThistleTea.Game.World.EntitySupervisorTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.EntitySupervisor

  describe "start_child/2" do
    test "routes unrelated entities across supervisor partitions" do
      [{first_key, first_supervisor}, {second_key, second_supervisor}] = distinct_partitions()

      assert {:ok, first_pid} = EntitySupervisor.start_child(first_key, {Agent, fn -> :first end})
      assert {:ok, second_pid} = EntitySupervisor.start_child(second_key, {Agent, fn -> :second end})

      assert first_supervisor != second_supervisor
      assert supervised_by?(first_supervisor, first_pid)
      assert supervised_by?(second_supervisor, second_pid)

      assert :ok = EntitySupervisor.terminate_child(first_pid)
      assert :ok = EntitySupervisor.terminate_child(second_pid)
    end
  end

  defp distinct_partitions do
    1..100
    |> Enum.map(&{&1, partition(&1)})
    |> Enum.uniq_by(&elem(&1, 1))
    |> Enum.take(2)
  end

  defp partition(key) do
    {:via, PartitionSupervisor, {EntitySupervisor, key}}
    |> GenServer.whereis()
  end

  defp supervised_by?(supervisor, child) do
    Enum.any?(DynamicSupervisor.which_children(supervisor), fn {_, pid, _, _} -> pid == child end)
  end
end
