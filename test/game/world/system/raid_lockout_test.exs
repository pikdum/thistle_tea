defmodule ThistleTea.Game.World.System.RaidLockoutTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Instance.Admission.Actor
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World.System.Instance

  setup [:start_raid_owner]

  describe "bind_raid/3" do
    test "survives empty cleanup and manual reset, then restores the same saved copy", %{server: server, guid: guid} do
      {:ok, world} = Instance.enter(249, guid, server)
      Instance.bind_raid(world, guid, server)
      assert_receive {:lockout, ^guid, :created}
      assert [%{map_id: 249, instance_id: id, seconds_remaining: seconds}] = Instance.saved_raids(guid, server)
      assert id == world.instance_id
      assert seconds == 446_400
      Instance.leave(guid, world, server)
      assert {:ok, %{reset: [], failed: []}} = Instance.reset(guid, server)
      refute_receive {:cleaned, ^world}, 30
      assert Instance.count(server) == 1
      assert {:ok, ^world} = Instance.resume(world, guid, server)
      Instance.bind_raid(world, guid, server)
      refute_receive {:lockout, ^guid, :created}, 10
    end

    test "publishes a new entrant's inherited save once", %{server: server, guid: guid} do
      {:ok, world} = Instance.enter(249, guid, server)
      Instance.bind_raid(world, guid, server)
      assert_receive {:lockout, ^guid, :created}
      other = guid + 1
      assert {:ok, ^world} = Instance.enter(249, other, server)
      assert_receive {:lockout, ^other, :created}
      assert [%{instance_id: id}] = Instance.saved_raids(other, server)
      assert id == world.instance_id
      assert {:ok, ^world} = Instance.enter(249, other, server)
      refute_receive {:lockout, ^other, :created}, 10
    end
  end

  describe "scheduled reset" do
    test "clears empty raids, preserves the shared period, and ignores stale timers", %{
      server: server,
      guid: guid,
      clock: clock
    } do
      {:ok, world} = Instance.enter(249, guid, server)
      Instance.bind_raid(world, guid, server)
      assert_receive {:lockout, ^guid, :created}
      Instance.leave(guid, world, server)
      state = :sys.get_state(server)
      {_ref, token} = state.reset_refs[249]
      deadline = state.reset_schedules[249].deadline
      Agent.update(clock, fn _ -> deadline end)
      send(server, {:raid_reset, 249, token})
      assert_receive {:lockout, ^guid, :expired}
      assert_receive {:cleaned, ^world}
      assert Instance.saved_raids(guid, server) == []
      assert Instance.count(server) == 0
      assert {:error, :instance_unavailable} = Instance.resume(world, guid, server)
      {:ok, next} = Instance.enter(249, guid, server)
      refute next == world
      send(server, {:raid_reset, 249, token})
      assert Instance.valid_member?(next, guid, server)
      assert :sys.get_state(server).reset_schedules[249].deadline == deadline + 5 * 86_400
    end

    test "invalidates occupied copies and cleans them only after the last departure", %{
      server: server,
      guid: guid,
      clock: clock
    } do
      {:ok, world} = Instance.enter(249, guid, server)
      Instance.bind_raid(world, guid, server)
      assert_receive {:lockout, ^guid, :created}
      state = :sys.get_state(server)
      {_ref, token} = state.reset_refs[249]
      Agent.update(clock, fn _ -> state.reset_schedules[249].deadline end)
      send(server, {:raid_reset, 249, token})
      assert_receive {:"$gen_cast", {:instance_membership_changed, ^world}}
      refute Instance.valid_member?(world, guid, server)
      refute_receive {:cleaned, ^world}, 10
      assert {:error, :instance_unavailable} = Instance.switch(guid, world, server)
      Instance.bind_raid(world, guid, server)
      assert Instance.saved_raids(guid, server) == []
      Instance.leave(guid, world, server)
      assert_receive {:cleaned, ^world}
      assert Instance.count(server) == 0
    end
  end

  defp start_raid_owner(_context) do
    parent = self()
    guid = System.unique_integer([:positive]) + 10_000_000
    Entity.register(guid)
    {:ok, clock} = start_supervised({Agent, fn -> 0 end})
    table = :ets.new(:raid_projection, [:set, :public])

    server =
      start_supervised!(
        {Instance,
         [
           name: nil,
           empty_timeout_ms: 1,
           owner: fn _ -> {:party, guid} end,
           reset_owner: fn _ -> {:ok, {:party, guid}} end,
           admission_actor: fn id -> %Actor{guid: id, account: id, raid?: true} end,
           admission_policy: fn _ -> %Policy{raid?: true} end,
           reset_days: fn _ -> 5 end,
           wall_clock: fn -> Agent.get(clock, & &1) end,
           group: fn _ -> %Group{id: guid, leader: guid} end,
           notify_lockout: fn id, reason -> send(parent, {:lockout, id, reason}) end,
           cleanup: fn world -> send(parent, {:cleaned, world}) end,
           script_name: fn _ -> nil end,
           projection_table: table
         ]}
      )

    %{server: server, guid: guid, clock: clock}
  end
end
