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
  end

  defp unique_name do
    :"instance_system_test_#{System.unique_integer([:positive])}"
  end
end
