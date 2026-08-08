defmodule ThistleTea.Game.World.System.InstanceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.InstanceData.Snapshot
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  describe "instance lifecycle" do
    test "cleans up an empty copy after its timeout" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_instance_system(name: name, empty_timeout_ms: 1, cleanup: fn world -> send(parent, {:cleaned, world}) end)

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
    end

    test "reuses a copy when its owner re-enters before cleanup" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 100,
          cleanup: fn world -> send(parent, {:cleaned, world}) end
        )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)
      assert {:ok, ^world} = InstanceSystem.enter(389, guid, name)

      refute_receive {:cleaned, ^world}, 150
      assert InstanceSystem.count(name) == 1
      assert %Snapshot{status: :no_instance_script} = InstanceData.read(world, [7], table)
    end

    test "resets an empty owned copy immediately" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 10_000,
          cleanup: fn world -> send(parent, {:cleaned, world}) end
        )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert {:ok, %{reset: [^world], failed: []}} = InstanceSystem.reset(guid, name)
      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
      assert %Snapshot{status: :missing_copy} = InstanceData.read(world, [7], table)
    end

    test "refuses to reset an occupied copy" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_instance_system(name: name, cleanup: fn world -> send(parent, {:cleaned, world}) end)

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      assert {:ok, %{reset: [], failed: [^world]}} = InstanceSystem.reset(guid, name)
      refute_receive {:cleaned, ^world}
    end

    test "switches a player into an existing copy" do
      name = unique_name()
      first_guid = System.unique_integer([:positive])
      second_guid = System.unique_integer([:positive])

      start_instance_system(name: name)

      assert {:ok, first_world} = InstanceSystem.enter(389, first_guid, name)
      assert {:ok, second_world} = InstanceSystem.enter(389, second_guid, name)
      assert :ok = InstanceSystem.switch(first_guid, second_world, name)

      assert InstanceSystem.info(first_guid, name).current == second_world
      refute first_world == second_world
    end

    test "uses the captured copy after the owner resolver changes" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      {:ok, owner} = start_supervised({Agent, fn -> {:party, 7} end})

      start_instance_system(
        name: name,
        owner: fn _guid -> Agent.get(owner, & &1) end,
        reset_owner: fn _guid -> {:ok, Agent.get(owner, & &1)} end
      )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)
      Agent.update(owner, fn _owner -> {:player, guid} end)

      assert InstanceSystem.world_for(389, guid, name) == world
      assert {:ok, ^world} = InstanceSystem.enter(389, guid, name)
      assert InstanceSystem.info(guid, name).copies |> Enum.any?(&(&1.world == world))
    end

    test "captures the map script only when a copy is created" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      {:ok, script_name} = start_supervised({Agent, fn -> "instance_stratholme" end})

      start_instance_system(
        name: name,
        script_name: fn _map_id -> Agent.get(script_name, & &1) end,
        owner: fn _guid -> {:player, guid} end
      )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      InstanceSystem.leave(guid, world, name)
      Agent.update(script_name, fn _name -> nil end)
      assert {:ok, ^world} = InstanceSystem.enter(329, guid, name)

      assert %{script_name: "instance_stratholme"} =
               InstanceSystem.info(guid, name).copies |> Enum.find(&(&1.world == world))
    end

    test "publishes commands after successful transitions and preserves rejected snapshots" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      table = start_instance_system(name: name, script_name: fn 329 -> "instance_stratholme" end)

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(world, [7], table)

      assert {:ok, 2} = InstanceSystem.command(world, 7, 2, :raw, name)
      assert %Snapshot{fields: %{7 => {:ok, 2}}} = InstanceData.read(world, [7], table)

      assert {:error, {:unsupported_field, 5}} = InstanceSystem.command(world, 5, 1, :raw, name)
      assert %Snapshot{fields: %{7 => {:ok, 2}}} = InstanceData.read(world, [7], table)
    end

    test "keeps copy projections isolated and removes timed-out data" do
      name = unique_name()
      first_guid = System.unique_integer([:positive])
      second_guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 1,
          script_name: fn 329 -> "instance_stratholme" end
        )

      assert {:ok, first} = InstanceSystem.enter(329, first_guid, name)
      assert {:ok, second} = InstanceSystem.enter(329, second_guid, name)
      assert {:ok, 1} = InstanceSystem.command(first, 7, 1, :raw, name)

      assert %Snapshot{fields: %{7 => {:ok, 1}}} = InstanceData.read(first, [7], table)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(second, [7], table)

      InstanceSystem.leave(first_guid, first, name)
      eventually(fn -> assert %Snapshot{status: :missing_copy} = InstanceData.read(first, [7], table) end)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(second, [7], table)
    end

    test "ignores stale cleanup after re-entry" do
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 50,
          script_name: fn 329 -> "instance_stratholme" end
        )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert {:ok, 1} = InstanceSystem.command(world, 7, 1, :raw, name)
      InstanceSystem.leave(guid, world, name)
      assert {:ok, ^world} = InstanceSystem.enter(329, guid, name)

      Process.sleep(75)
      assert %Snapshot{fields: %{7 => {:ok, 1}}} = InstanceData.read(world, [7], table)
    end
  end

  defp start_instance_system(options) do
    table = :ets.new(:instance_system_projection, [:set, :public, read_concurrency: true])
    start_supervised!({InstanceSystem, Keyword.put(options, :projection_table, table)})
    table
  end

  defp eventually(assertion, attempts \\ 20)
  defp eventually(assertion, 0), do: assertion.()

  defp eventually(assertion, attempts) do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(5)
      eventually(assertion, attempts - 1)
  end

  defp unique_name do
    :"instance_system_test_#{System.unique_integer([:positive])}"
  end
end
