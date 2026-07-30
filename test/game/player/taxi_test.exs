defmodule ThistleTea.Game.Player.TaxiTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgNewTaxiPath
  alias ThistleTea.Game.Network.Message.SmsgShowtaxinodes
  alias ThistleTea.Game.Network.Message.SmsgTaxinodeStatus
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup do
    flightmaster_guid = Guid.from_low_guid(:mob, 352, System.unique_integer([:positive, :monotonic]))
    character_id = System.unique_integer([:positive, :monotonic])
    character = character(character_id) |> CharacterStore.put()

    Metadata.put(flightmaster_guid, %{npc_flags: 0x8, alive?: true})
    SpatialHash.update(:mobs, flightmaster_guid, WorldRef.open(0), 2.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(flightmaster_guid)
      SpatialHash.remove(:mobs, flightmaster_guid)
    end)

    %{character: character, flightmaster_guid: flightmaster_guid}
  end

  describe "query/3" do
    test "discovers an unknown nearby node before opening the menu", context do
      state = %{ready: true, character: context.character}
      state = Taxi.query(state, context.flightmaster_guid, network())

      assert Taxi.known?(state.character, 2)
      assert CharacterStore.get(state.character.id).player.taxi_nodes == MapSet.new([2])
      assert_receive {:"$gen_cast", {:send_packet, %SmsgNewTaxiPath{}}}

      assert_receive {:"$gen_cast", {:send_packet, %SmsgTaxinodeStatus{guid: guid, known?: true}}}

      assert guid == context.flightmaster_guid
    end

    test "opens the taxi map for a known node", context do
      character = put_known(context.character, [2, 4])
      state = Taxi.query(%{ready: true, character: character}, context.flightmaster_guid, network())

      assert state.character == character

      assert_receive {:"$gen_cast", {:send_packet, %SmsgShowtaxinodes{guid: guid, nearest_node: 2, nodes: nodes}}}

      assert guid == context.flightmaster_guid
      assert nodes == [0b1010, 0, 0, 0, 0, 0, 0, 0]
    end

    test "ignores a creature without the flight-master flag", context do
      Metadata.update(context.flightmaster_guid, %{npc_flags: 0})
      state = %{ready: true, character: context.character}

      assert Taxi.query(state, context.flightmaster_guid, network()) == state
      refute_receive {:"$gen_cast", _message}
    end
  end

  describe "status/3" do
    test "reports whether the nearest node is known", context do
      character = put_known(context.character, [2])
      Taxi.status(%{ready: true, character: character}, context.flightmaster_guid, network())

      assert_receive {:"$gen_cast", {:send_packet, %SmsgTaxinodeStatus{guid: guid, known?: true}}}

      assert guid == context.flightmaster_guid
    end
  end

  describe "unlock_all/2" do
    test "persists every discoverable node", context do
      state = Taxi.unlock_all(%{character: context.character}, network())

      assert state.character.player.taxi_nodes == MapSet.new([2, 4])
      assert CharacterStore.get(state.character.id).player.taxi_nodes == MapSet.new([2, 4])
    end
  end

  defp character(id) do
    %Character{
      id: id,
      account_id: 1,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{race: 1},
      player: %Player{taxi_nodes: MapSet.new()},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp put_known(%Character{player: player} = character, nodes) do
    %{character | player: %{player | taxi_nodes: MapSet.new(nodes)}}
  end

  defp network do
    nodes = [
      %Node{
        id: 2,
        map_id: 0,
        position: {2.0, 0.0, 0.0},
        name: "Stormwind",
        mount_display_ids: %{alliance: 6852, horde: 0}
      },
      %Node{
        id: 4,
        map_id: 0,
        position: {100.0, 0.0, 0.0},
        name: "Westfall",
        mount_display_ids: %{alliance: 6852, horde: 0}
      }
    ]

    Network.build(nodes, [], %{}, [])
  end
end
