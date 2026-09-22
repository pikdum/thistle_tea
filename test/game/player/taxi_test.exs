defmodule ThistleTea.Game.Player.TaxiTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode
  alias ThistleTea.Game.Entity.Logic.Reputation
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgSetActiveMover
  alias ThistleTea.Game.Network.Message.SmsgActivatetaxireply
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.Network.Message.SmsgNewTaxiPath
  alias ThistleTea.Game.Network.Message.SmsgShowtaxinodes
  alias ThistleTea.Game.Network.Message.SmsgTaxinodeStatus
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup do
    flightmaster_guid = Guid.from_low_guid(:mob, 352, System.unique_integer([:positive, :monotonic]))
    character_id = System.unique_integer([:positive, :monotonic])
    character = character(character_id) |> CharacterStore.put()
    Entity.register(character.object.guid)

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
      assert Position.projection(character.object.guid)

      token = state.character.internal.taxi_flight.token
      state = Taxi.arrive(state, token)
      assert Taxi.arrive(state, token) == state

      assert state.character.movement_block.position == {100.0, 0.0, 0.0, 0.0}
      assert state.character.unit.mount_display_id == 0
      refute state.character.internal.taxi_flight
      refute Position.projection(character.object.guid)
      assert CharacterStore.get(state.character.id).player.coinage == 75
      assert_receive :restore_companion

      if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)
    end

    test "rounds the honored flightmaster discount for each path", context do
      previous_catalog = ReputationLoader.catalog()

      catalog = %Catalog{
        factions: %{
          72 => %Definition{id: 72, index: 19, variants: [%Variant{}]}
        }
      }

      ReputationLoader.put_catalog(catalog)
      on_exit(fn -> ReputationLoader.put_catalog(previous_catalog) end)

      reputation = Reputation.initialize(catalog, 1, 1)
      {reputation, _changes} = Reputation.set(reputation, catalog, 72, 9_000, %{race: 1, class: 1})

      character =
        context.character
        |> put_known([2, 4])
        |> then(&%{&1 | player: %{&1.player | reputation: reputation}})

      Metadata.update(context.flightmaster_guid, %{
        faction_template: %FactionTemplate{faction: 72}
      })

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      state = Taxi.activate(state, context.flightmaster_guid, [2, 4], network())

      assert state.character.player.coinage == 77

      state = Taxi.disconnect(state)
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

  describe "spline_done/2" do
    setup [:start_flight]

    test "rejects early, obsolete, foreign-mover, and loading acknowledgements", %{flight_state: state} do
      spline_id = state.character.internal.spline_id

      assert Taxi.spline_done(state, spline_id) == state
      assert Taxi.spline_done(state, spline_id + 1) == state

      expired = expire_flight(state)
      loading = %{expired | ready: false}
      foreign = %{expired | active_mover_guid: state.guid + 1}

      assert Taxi.spline_done(expired, spline_id + 1) == expired
      assert Taxi.spline_done(loading, spline_id) == loading
      assert Taxi.spline_done(foreign, spline_id) == foreign
    end

    test "finishes the matching elapsed flight once at the server destination", %{flight_state: state} do
      state = expire_flight(state)
      spline_id = state.character.internal.spline_id
      landed = Taxi.spline_done(state, spline_id)

      refute landed.character.internal.taxi_flight
      assert landed.character.movement_block.position == {100.0, 0.0, 0.0, 0.0}
      assert landed.character.unit.mount_display_id == 0
      assert landed.character.player.coinage == 75
      assert CharacterStore.get(state.character.id).movement_block.position == {100.0, 0.0, 0.0, 0.0}
      assert_receive :restore_companion
      assert Taxi.spline_done(landed, spline_id) == landed
      refute_receive :restore_companion

      if is_reference(landed.player_tick_ref), do: Process.cancel_timer(landed.player_tick_ref)
    end
  end

  describe "start_path/3" do
    test "charges a scripted route without requiring known nodes", context do
      character = context.character

      state = %State{
        ready: true,
        guid: character.object.guid,
        character: character,
        visibility_cells: MapSet.new()
      }

      state = Taxi.start_path(state, 12, network())

      assert state.character.player.coinage == 75
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
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 4}}}
    end
  end

  describe "start_path/4" do
    test "allows a mountless spell route from an unpositioned source", context do
      network = network()

      source = %{
        network.nodes[2]
        | position: {0.0, 0.0, 0.0},
          map_id: 131_074,
          mount_display_ids: %{alliance: 0, horde: 0}
      }

      network = %{network | nodes: Map.put(network.nodes, 2, source)}
      state = ready_state(context.character)

      assert Taxi.start_path(state, 12, network) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 2}}}
      flying = Taxi.start_path(state, 12, network, spell_id: 28_129)
      assert flying.character.internal.taxi_flight.path_ids == [12]
      assert flying.character.unit.mount_display_id == 0
      assert flying.character.player.coinage == 75
      assert flying.character.player.taxi_nodes == MapSet.new()
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 0}}}
      finish_test_flight(flying)
    end

    test "scripted routes use an opposite-faction mount when needed", context do
      character = context.character
      character = put_in(character.unit.race, 2)
      flying = Taxi.start_path(ready_state(character), 12, network(), spell_id: 27_998)
      assert flying.character.unit.mount_display_id == 6852
      finish_test_flight(flying)
    end

    test "preserves the delivering spell and cancels another cast", context do
      for {cast_id, retained?} <- [{27_998, true}, {8690, false}] do
        cast = Cast.new(%Spell{id: cast_id}, Target.self(context.character.object.guid), Time.now())
        character = context.character
        character = put_in(character.internal.casting, cast)
        flying = Taxi.start_path(ready_state(character), 12, network(), spell_id: 27_998)
        assert flying.character.internal.casting == cast == retained?
        finish_test_flight(flying)
      end
    end

    test "rejects unavailable players and insufficient fares without changing their state", context do
      state = ready_state(context.character)

      for invalid <- [
            %{state | logout_timer: make_ref()},
            put_in(state.character.unit.flags, 0x00000004),
            put_in(state.character.unit.health, 0),
            put_in(state.character.internal.in_combat, true)
          ] do
        assert Taxi.start_path(invalid, 12, network(), spell_id: 27_998) == invalid
        assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 7}}}
      end

      poor = put_in(state.character.player.coinage, 24)
      assert Taxi.start_path(poor, 12, network(), spell_id: 27_998) == poor
      assert_receive {:"$gen_cast", {:send_packet, %SmsgActivatetaxireply{reply: 3}}}
    end
  end

  describe "disconnect/1" do
    setup [:start_flight]

    test "stops projection and rejects callbacks from the old flight", %{flight_state: flying} do
      token = flying.character.internal.taxi_flight.token
      spline_id = flying.character.internal.spline_id
      paused = Taxi.disconnect(flying)

      assert paused.taxi_arrival_ref == nil
      assert Process.read_timer(flying.taxi_arrival_ref) == false
      refute Position.projection(flying.guid)
      assert paused.character.internal.taxi_flight.remaining_nodes != []
      assert Taxi.arrive(paused, token) == paused
      assert Taxi.progress(paused, token) == paused
      assert Taxi.spline_done(paused, spline_id) == paused
    end

    test "world teardown saves the checkpoint before discarding movement", %{flight_state: flying} do
      assert State.leave_world(flying) == %State{}
      saved = CharacterStore.get(flying.character.id)
      assert saved.internal.taxi_flight.remaining_nodes != []
      assert saved.internal.taxi_flight.started_at == nil
      assert saved.internal.movement_start_time == nil
      assert saved.movement_block.spline_nodes == []
      assert saved.movement_block.position != {100.0, 0.0, 0.0, 0.0}
      assert saved.player.coinage == 75
      assert saved.unit.mount_display_id == 6852
      refute Position.projection(flying.guid)
    end
  end

  describe "resume/1" do
    setup [:start_flight]

    test "starts once after the client's active mover and finishes under a fresh token", %{flight_state: flying} do
      old_token = flying.character.internal.taxi_flight.token
      old_spline_id = flying.character.internal.spline_id
      paused = Taxi.disconnect(flying)
      loading = %{paused | ready: false}
      assert Taxi.resume(loading) == loading
      assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{}}}

      message = %CmsgSetActiveMover{guid: flying.guid}
      resumed = CmsgSetActiveMover.handle(message, loading)
      new_token = resumed.character.internal.taxi_flight.token

      assert new_token != old_token
      assert resumed.character.internal.spline_id != old_spline_id
      assert resumed.character.player.coinage == 75
      assert resumed.character.player.taxi_nodes == flying.character.player.taxi_nodes
      assert resumed.character.internal.taxi_flight.remaining_nodes == nil
      assert is_reference(resumed.taxi_arrival_ref)
      assert Position.projection(resumed.guid)
      assert CharacterStore.get(resumed.character.id).internal.taxi_flight.token == new_token
      assert_receive {:"$gen_cast", {:send_packet, %SmsgMonsterMove{}}}
      assert CmsgSetActiveMover.handle(message, resumed) == resumed
      assert Taxi.arrive(resumed, old_token) == resumed
      assert Taxi.progress(resumed, old_token) == resumed
      assert Taxi.spline_done(resumed, old_spline_id) == resumed

      landed = resumed |> expire_flight() |> Taxi.progress(new_token)
      assert landed.character.internal.taxi_flight == nil
      assert landed.character.movement_block.position == {100.0, 0.0, 0.0, 0.0}
      assert landed.character.unit.mount_display_id == 0
      assert landed.character.player.coinage == 75
      refute Position.projection(landed.guid)
      finish_test_flight(landed)
    end
  end

  describe "cancel/1" do
    setup [:start_flight]

    test "discards the route without advancing to its destination", %{flight_state: flying} do
      canceled = Taxi.cancel(flying)
      assert canceled.taxi_arrival_ref == nil
      assert canceled.character.internal.taxi_flight == nil
      assert canceled.character.movement_block.position != {100.0, 0.0, 0.0, 0.0}
      refute Position.projection(canceled.guid)
      assert Taxi.resume(canceled) == canceled
    end
  end

  defp ready_state(character) do
    %State{ready: true, guid: character.object.guid, character: character, visibility_cells: MapSet.new()}
  end

  defp finish_test_flight(state) do
    state = Taxi.disconnect(state)
    if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)
    state
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

  defp start_flight(context) do
    character = put_known(context.character, [2, 4])
    state = %State{ready: true, guid: character.object.guid, character: character, visibility_cells: MapSet.new()}
    state = Taxi.activate(state, context.flightmaster_guid, [2, 4], network())

    on_exit(fn ->
      Process.cancel_timer(state.taxi_arrival_ref)
      if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)
    end)

    %{flight_state: state}
  end

  defp expire_flight(state) do
    internal = state.character.internal
    flight = internal.taxi_flight
    started_at = Time.now() - flight.duration_ms - 1
    flight = %{flight | started_at: started_at}
    internal = %{internal | taxi_flight: flight, movement_start_time: started_at}
    %{state | character: %{state.character | internal: internal}}
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
