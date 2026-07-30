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
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgActivatetaxireply
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
    SpatialHash.update(:players, character.object.guid, WorldRef.open(0), 0.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(flightmaster_guid)
      SpatialHash.remove(:mobs, flightmaster_guid)
      SpatialHash.remove(:players, character.object.guid)
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

  describe "activate/4" do
    test "starts and completes a paid flight", context do
      character = put_known(context.character, [2, 4])

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      state = Taxi.activate(state, context.flightmaster_guid, [2, 4], network())

      assert state.character.player.coinage == 75
      assert state.character.unit.mount_display_id == 6852
      assert state.character.internal.taxi_flight
      assert is_reference(state.taxi_arrival_ref)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 0}}}
      assert SpatialHash.get_movement(character.object.guid)

      token = state.character.internal.taxi_flight.token
      state = Taxi.arrive(state, token)

      assert state.character.movement_block.position == {100.0, 0.0, 0.0, 0.0}
      assert state.character.unit.mount_display_id == 0
      refute state.character.internal.taxi_flight
      refute SpatialHash.get_movement(character.object.guid)
      assert CharacterStore.get(state.character.id).player.coinage == 75
      assert_receive :restore_companion

      if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)
    end

    test "rejects a route through an unknown node", context do
      character = put_known(context.character, [2])

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      assert Taxi.activate(state, context.flightmaster_guid, [2, 4], network()) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 6}}}
    end
  end

  describe "start_path/3" do
    test "starts a free scripted path without requiring known nodes", context do
      character = context.character

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      state = Taxi.start_path(state, 12, network())

      assert state.character.player.coinage == 100
      assert state.character.internal.taxi_flight.path_ids == [12]
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 0}}}

      state = Taxi.disconnect(state)
      if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)
    end

    test "rejects a scripted path away from its source", context do
      character = %{
        context.character
        | movement_block: %{context.character.movement_block | position: {1_000.0, 0.0, 0.0, 0.0}}
      }

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      assert Taxi.start_path(state, 12, network()) == state
      refute_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{}}}
    end
  end

  defp character(id) do
    %Character{
      id: id,
      account_id: 1,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{
        race: 1,
        level: 1,
        health: 100,
        flags: 0,
        mount_display_id: 0,
        shapeshift_form: 0,
        stand_state: 0
      },
      player: %Player{taxi_nodes: MapSet.new(), coinage: 100},
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

    path = %Path{
      id: 12,
      source_node_id: 2,
      destination_node_id: 4,
      cost: 25,
      nodes: [
        %PathNode{index: 0, map_id: 0, position: {2.0, 0.0, 0.0}},
        %PathNode{index: 1, map_id: 0, position: {100.0, 0.0, 0.0}}
      ]
    }

    Network.build(nodes, [path], %{}, [])
  end
end
