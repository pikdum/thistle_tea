defmodule ThistleTea.Game.Entity.Server.TransportTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

  describe "route ownership" do
    test "publishes and advances an authoritative ship pose" do
      entry = :erlang.unique_integer([:positive])
      route = TransportLogic.build_ship(entry, "Test Ship", 10, ship_nodes(), 10, 1, 20_000)
      entity = GameObject.build_transport(template(entry), TransportLogic.pose_at(route, 0))
      clock = fn -> 1_000 end

      {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: clock})
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, initial} = Entity.call(entity.object.guid, :transport_info)
      assert initial.progress_ms == 0
      assert initial.world == WorldRef.open(0)

      assert {:ok, advanced} = Transports.advance(entity.object.guid, 3_000)
      assert advanced.progress_ms == 3_000
      assert elem(advanced.position, 0) > 0.0

      world = WorldRef.open(0)
      assert {^world, x, _y, _z} = World.position(entity.object.guid)
      assert_in_delta x, elem(advanced.position, 0), 0.000001
      assert Transports.get(entity.object.guid).progress_ms == 3_000
    end
  end

  defp template(entry) do
    %GameObjectTemplate{
      entry: entry,
      type: 15,
      display_id: 3015,
      name: "Test Ship",
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [10, 10, 1] ++ List.duplicate(0, 21)
    }
  end

  defp ship_nodes do
    [
      node(0, {-10.0, 0.0, 0.0}, 0, 0),
      node(1, {0.0, 0.0, 0.0}, 2, 2),
      node(2, {10.0, 0.0, 0.0}, 0, 0),
      node(3, {20.0, 0.0, 0.0}, 2, 2),
      node(4, {10.0, 0.0, 0.0}, 0, 0),
      node(5, {0.0, 0.0, 0.0}, 2, 2)
    ]
  end

  defp node(index, position, flags, delay) do
    %{node_index: index, map_id: 0, position: position, flags: flags, delay: delay}
  end
end
