defmodule ThistleTea.Game.World.CreatureGroupsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.WorldRef

  setup [:groups]

  describe "event/4" do
    test "coordinates combat only within the same world copy", %{server: server, world: world} do
      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      other = mob(WorldRef.instance(world.map_id, 2), 2, 202)
      Enum.each([a, b, other], &CreatureGroups.register(&1, self(), server))
      CreatureGroups.event(a, {:attack, 99}, self(), server)
      assert_receive {:creature_group, token, {:attack, 99}}
      assert CreatureGroups.valid_command?(world, 102, token, self(), server)
      refute CreatureGroups.valid_command?(other.internal.world, 202, token, self(), server)
      CreatureGroups.event(a, {:attack, 99}, self(), server)
      CreatureGroups.snapshot(world, 101, server)
      refute_receive {:creature_group, _, _}
    end

    test "tracks deaths, respawns, and group-dead conditions", %{server: server, world: world} do
      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      Enum.each([a, b], &CreatureGroups.register(&1, self(), server))
      refute CreatureGroups.snapshot(world, 101, server).dead?
      CreatureGroups.event(b, :death, self(), server)
      assert CreatureGroups.snapshot(world, 101, server).dead?
      CreatureGroups.event(a, :death, self(), server)
      CreatureGroups.event(b, :respawn, self(), server)
      assert_receive {:creature_group, _, :respawn}
      CreatureGroups.event(a, :respawn, self(), server)
      refute CreatureGroups.snapshot(world, 101, server).dead?
      refute_receive {:creature_group, _, :respawn}
    end

    test "rejects stale owners and invalidates commands after reincarnation", %{server: server, world: world} do
      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      Enum.each([a, b], &CreatureGroups.register(&1, self(), server))
      CreatureGroups.event(a, {:attack, 99}, self(), server)
      assert_receive {:creature_group, token, {:attack, 99}}
      replacement = mob(world, 2, 103)
      CreatureGroups.register(replacement, self(), server)
      refute CreatureGroups.valid_command?(world, 103, token, self(), server)
      CreatureGroups.event(b, :death, self(), server)
      refute CreatureGroups.snapshot(world, 101, server).dead?
      CreatureGroups.event(replacement, :death, server, server)
      refute CreatureGroups.snapshot(world, 101, server).dead?
    end
  end

  describe "respawn/3" do
    test "renews membership tokens and revives dead companions even on a forced living respawn", %{
      server: server,
      world: world
    } do
      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      Enum.each([a, b], &CreatureGroups.register(&1, self(), server))
      CreatureGroups.event(b, {:attack, 99}, self(), server)
      assert_receive {:creature_group, token, {:attack, 99}}
      CreatureGroups.event(b, :death, self(), server)
      CreatureGroups.respawn(a, self(), server)
      refute CreatureGroups.valid_command?(world, 101, token, self(), server)
      assert_receive {:creature_group, _, :respawn}
    end
  end

  describe "handle_info/2" do
    test "an unloaded companion no longer prevents the group-dead condition", %{server: server, world: world} do
      parent = self()

      owner =
        spawn(fn ->
          receive do
            :stop -> send(parent, :owner_stopped)
          end
        end)

      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      CreatureGroups.register(a, self(), server)
      CreatureGroups.register(b, owner, server)
      refute CreatureGroups.snapshot(world, 101, server).dead?
      send(owner, :stop)
      assert_receive :owner_stopped
      await_absent(server, world, 102, 100)
      assert CreatureGroups.snapshot(world, 101, server).dead?
      CreatureGroups.register(b, self(), server)
      refute CreatureGroups.snapshot(world, 101, server).dead?
    end
  end

  describe "leave/4" do
    test "removal survives reload and invalidates queued commands", %{server: server, world: world} do
      a = mob(world, 1, 101)
      b = mob(world, 2, 102)
      Enum.each([a, b], &CreatureGroups.register(&1, self(), server))
      CreatureGroups.event(a, {:attack, 99}, self(), server)
      assert_receive {:creature_group, token, {:attack, 99}}
      assert :ok = CreatureGroups.leave(world, 102, self(), server)
      refute CreatureGroups.valid_command?(world, 102, token, self(), server)
      CreatureGroups.register(b, self(), server)
      assert CreatureGroups.snapshot(world, 102, server) == %{leader: nil, dead?: true}
      assert :ok = CreatureGroups.join(world, 102, 101, %Member{flags: 2}, self(), server)
      refute CreatureGroups.valid_command?(world, 102, token, self(), server)
      assert CreatureGroups.snapshot(world, 102, server).leader == 1
    end

    test "the original leader disbands every member", %{server: server, world: world} do
      Enum.each([mob(world, 1, 101), mob(world, 2, 102)], &CreatureGroups.register(&1, self(), server))
      CreatureGroups.leave(world, 101, self(), server)
      assert CreatureGroups.snapshot(world, 102, server) == %{leader: nil, dead?: true}
      CreatureGroups.register(mob(world, 2, 102), self(), server)
      assert CreatureGroups.snapshot(world, 102, server).leader == nil
      CreatureGroups.stop_world(world, server)
      CreatureGroups.register(mob(world, 2, 102), self(), server)
      assert CreatureGroups.snapshot(world, 102, server).leader == 1
    end
  end

  describe "join/6" do
    test "supports runtime summons and rejects cross-instance joins", %{server: server, world: world} do
      leader = mob(world, nil, 301)
      member = mob(world, nil, 302)
      other = mob(WorldRef.instance(world.map_id, 2), nil, 303)
      Enum.each([leader, member, other], &CreatureGroups.register(&1, self(), server))
      assert {:error, :invalid_membership} = CreatureGroups.join(world, 302, 303, %Member{}, self(), server)
      assert :ok = CreatureGroups.join(world, 302, 301, %Member{flags: 2}, self(), server)
      assert CreatureGroups.snapshot(world, 302, server).leader == {:runtime, 301}
      assert {:error, :invalid_membership} = CreatureGroups.join(world, 302, 301, %Member{}, self(), server)
    end
  end

  defp groups(_context) do
    group = CreatureGroup.new(1) |> CreatureGroup.add(2, %Member{flags: 14})
    catalog = fn _map, id -> if id in [1, 2], do: group end
    server = start_supervised!({CreatureGroups, name: nil, catalog: catalog})
    %{server: server, world: WorldRef.instance(36, 1)}
  end

  defp await_absent(server, world, guid, attempts) when attempts > 0 do
    if CreatureGroups.snapshot(world, guid, server) do
      Process.sleep(5)
      await_absent(server, world, guid, attempts - 1)
    end
  end

  defp await_absent(_server, _world, _guid, 0), do: flunk("creature owner was not removed")

  defp mob(world, id, guid) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100},
      internal: %Internal{world: world, creature: %Creature{db_guid: id}}
    }
  end
end
