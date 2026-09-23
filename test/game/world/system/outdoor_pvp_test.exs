defmodule ThistleTea.Game.World.System.OutdoorPvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.OutdoorPvp.ResourceRace
  alias ThistleTea.Game.World.System.OutdoorPvp
  alias ThistleTea.Game.WorldRef

  setup [:server]

  describe "contribute/5" do
    test "serializes contributions, rejects replays, and switches control at the limit", %{server: server} do
      world = WorldRef.open(1)
      OutdoorPvp.sync(1, world, 1377, :alliance, server)
      assert {:ok, :contributed} = OutdoorPvp.contribute(1, world, :alliance, :first, server)
      assert_receive :refresh_outdoor_pvp
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, world, :alliance, :first, server)
      assert OutdoorPvp.world_states(1377, server) == [{2313, 1}, {2314, 0}, {2317, 2}]
      assert {:ok, :captured} = OutdoorPvp.contribute(1, world, :alliance, :second, server)
      assert OutdoorPvp.snapshot(server) == %ResourceRace{limit: 2, controller: :alliance}
      assert OutdoorPvp.sync(1, world, 1377, :alliance, server).favor?
      refute OutdoorPvp.sync(2, world, 1377, :horde, server).favor?
      assert {:ok, :contributed} = OutdoorPvp.contribute(2, world, :horde, :third, server)
      assert {:ok, :captured} = OutdoorPvp.contribute(2, world, :horde, :fourth, server)
      refute OutdoorPvp.sync(1, world, 1377, :alliance, server).favor?
      assert OutdoorPvp.sync(2, world, 1377, :horde, server).favor?
    end

    test "requires the registered owner, faction, zone, and continent", %{server: server} do
      world = WorldRef.open(1)
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, world, :alliance, :first, server)
      OutdoorPvp.sync(1, world, 1377, :alliance, server)
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, world, :horde, :first, server)
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, WorldRef.open(0), :alliance, :first, server)
      task = Task.async(fn -> OutdoorPvp.contribute(1, world, :alliance, :first, server) end)
      assert {:error, :unavailable} = Task.await(task)
      OutdoorPvp.sync(1, WorldRef.instance(531, 1), 3428, :alliance, server)
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, world, :alliance, :first, server)
      OutdoorPvp.leave(1, server)
      assert {:error, :unavailable} = OutdoorPvp.contribute(1, world, :alliance, :first, server)
      assert OutdoorPvp.snapshot(server).alliance == 0
    end
  end

  describe "sync/5" do
    test "projects progress only in Silithus and clears it on exit", %{server: server} do
      world = WorldRef.open(1)
      assert OutdoorPvp.sync(1, world, 1377, :alliance, server).states == [{2313, 0}, {2314, 0}, {2317, 2}]

      assert OutdoorPvp.sync(1, world, 14, :alliance, server) == %{
               favor?: false,
               states: [{2313, 0}, {2314, 0}, {2317, 0}]
             }

      assert OutdoorPvp.world_states(14, server) == []
    end

    test "restores the winner's buff in both Ahn'Qiraj zones" do
      server = start_supervised!({OutdoorPvp, name: nil, race: %ResourceRace{controller: :alliance}}, id: :controlled)

      for {map, zone} <- [{531, 3428}, {509, 3429}] do
        assert OutdoorPvp.sync(1, WorldRef.instance(map, 1), zone, :alliance, server).favor?
        refute OutdoorPvp.sync(2, WorldRef.instance(map, 1), zone, :horde, server).favor?
      end
    end
  end

  defp server(_context), do: %{server: start_supervised!({OutdoorPvp, name: nil, race: %ResourceRace{limit: 2}})}
end
