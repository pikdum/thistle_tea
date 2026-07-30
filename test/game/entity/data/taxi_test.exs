defmodule ThistleTea.Game.Entity.Data.TaxiTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode

  describe "build/4" do
    test "excludes nodes whose outgoing routes are all spell taxi paths" do
      network =
        Network.build(
          [taxi_node(1), taxi_node(2), taxi_node(3)],
          [path(10, 1, 2), path(20, 2, 3)],
          %{},
          [10]
        )

      refute MapSet.member?(network.network_node_ids, 1)
      assert MapSet.member?(network.network_node_ids, 2)
      assert MapSet.member?(network.network_node_ids, 3)
    end
  end

  describe "itinerary/2" do
    test "returns a direct path" do
      route = path(10, 1, 2)
      network = Network.build([taxi_node(1), taxi_node(2)], [route], %{}, [])

      assert {:ok, %{paths: [^route], nodes: nodes, total_cost: 10}} = Network.itinerary(network, [1, 2])
      assert Enum.map(nodes, & &1.index) == [0, 1, 2, 3]
    end

    test "splices express legs at VMangos transition points" do
      first = path(10, 1, 2)
      second = path(20, 2, 3)
      network = Network.build([taxi_node(1), taxi_node(2), taxi_node(3)], [first, second], %{{10, 20} => {2, 1}}, [])

      assert {:ok, %{nodes: nodes, total_cost: 30}} = Network.itinerary(network, [1, 2, 3])

      assert Enum.map(nodes, & &1.position) == [
               {10.0, 0.0, 0.0},
               {10.0, 1.0, 0.0},
               {10.0, 2.0, 0.0},
               {20.0, 1.0, 0.0},
               {20.0, 2.0, 0.0},
               {20.0, 3.0, 0.0}
             ]
    end

    test "rejects a missing leg" do
      network = Network.build([taxi_node(1), taxi_node(2), taxi_node(3)], [path(10, 1, 2)], %{}, [])
      assert {:error, :no_such_path} = Network.itinerary(network, [1, 2, 3])
    end
  end

  describe "nearest_node/4" do
    test "only considers nodes with a mount for the player's team" do
      nodes = [
        taxi_node(1, {1.0, 0.0, 0.0}, %{alliance: 0, horde: 100}),
        taxi_node(2, {2.0, 0.0, 0.0}, %{alliance: 200, horde: 0})
      ]

      network = Network.build(nodes, [], %{}, [])

      assert %Node{id: 2} = Network.nearest_node(network, 0, {0.0, 0.0, 0.0}, :alliance)
      assert %Node{id: 1} = Network.nearest_node(network, 0, {0.0, 0.0, 0.0}, :horde)
    end
  end

  describe "mask/2" do
    test "encodes known network nodes into eight 32-bit words" do
      network = Network.build([taxi_node(1), taxi_node(32), taxi_node(33), taxi_node(257)], [], %{}, [])

      assert Network.mask(network, [1, 32, 33, 257]) == [
               0x80000001,
               0x00000001,
               0,
               0,
               0,
               0,
               0,
               0
             ]
    end
  end

  defp taxi_node(id, position \\ {0.0, 0.0, 0.0}, mounts \\ %{alliance: 1, horde: 1}) do
    %Node{id: id, map_id: 0, position: position, name: "Node #{id}", mount_display_ids: mounts}
  end

  defp path(id, source, destination) do
    %Path{
      id: id,
      source_node_id: source,
      destination_node_id: destination,
      cost: id,
      nodes:
        Enum.map(0..3, fn index ->
          %PathNode{index: index, map_id: 0, position: {id * 1.0, index * 1.0, 0.0}}
        end)
    }
  end
end
