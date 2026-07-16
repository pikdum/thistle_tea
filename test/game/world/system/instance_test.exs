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
  end

  defp unique_name do
    :"instance_system_test_#{System.unique_integer([:positive])}"
  end
end
