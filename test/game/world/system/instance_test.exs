defmodule ThistleTea.Game.World.System.InstanceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  describe "instance lifecycle" do
    test "cleans up an empty copy after its timeout" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_supervised!(
        {InstanceSystem, name: name, empty_timeout_ms: 1, cleanup: fn world -> send(parent, {:cleaned, world}) end}
      )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
    end

    test "reuses a copy when its owner re-enters before cleanup" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_supervised!(
        {InstanceSystem, name: name, empty_timeout_ms: 100, cleanup: fn world -> send(parent, {:cleaned, world}) end}
      )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)
      assert {:ok, ^world} = InstanceSystem.enter(389, guid, name)

      refute_receive {:cleaned, ^world}, 150
      assert InstanceSystem.count(name) == 1
    end

    test "resets an empty owned copy immediately" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_supervised!(
        {InstanceSystem, name: name, empty_timeout_ms: 10_000, cleanup: fn world -> send(parent, {:cleaned, world}) end}
      )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert {:ok, %{reset: [^world], failed: []}} = InstanceSystem.reset(guid, name)
      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
    end

    test "refuses to reset an occupied copy" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_supervised!({InstanceSystem, name: name, cleanup: fn world -> send(parent, {:cleaned, world}) end})

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      assert {:ok, %{reset: [], failed: [^world]}} = InstanceSystem.reset(guid, name)
      refute_receive {:cleaned, ^world}
    end

    test "switches a player into an existing copy" do
      name = unique_name()
      first_guid = System.unique_integer([:positive])
      second_guid = System.unique_integer([:positive])

      start_supervised!({InstanceSystem, name: name})

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

      start_supervised!(
        {InstanceSystem,
         name: name,
         owner: fn _guid -> Agent.get(owner, & &1) end,
         reset_owner: fn _guid -> {:ok, Agent.get(owner, & &1)} end}
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

      start_supervised!(
        {InstanceSystem,
         name: name, script_name: fn _map_id -> Agent.get(script_name, & &1) end, owner: fn _guid -> {:player, guid} end}
      )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      InstanceSystem.leave(guid, world, name)
      Agent.update(script_name, fn _name -> nil end)
      assert {:ok, ^world} = InstanceSystem.enter(329, guid, name)

      assert %{script_name: "instance_stratholme"} =
               InstanceSystem.info(guid, name).copies |> Enum.find(&(&1.world == world))
    end
  end

  defp unique_name do
    :"instance_system_test_#{System.unique_integer([:positive])}"
  end
end
