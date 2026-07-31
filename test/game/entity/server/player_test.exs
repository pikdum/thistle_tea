defmodule ThistleTea.Game.Entity.Server.PlayerTest do
  use ExUnit.Case, async: true
  use ThistleTea.Game.Network.Opcodes, [:SMSG_LOGOUT_COMPLETE, :SMSG_UPDATE_OBJECT]

  alias ThistleTea.Account
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Companion, as: CompanionLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.Rest, as: RestLogic
  alias ThistleTea.Game.Entity.Logic.Transport
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Monitor, as: CompanionMonitor
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.Server.PlayerSupervisor
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "login/3" do
    test "starts the registered owner of a character" do
      {:ok, account} = Account.get_user("test")
      id = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:player, id)
      character = CharacterStore.put(login_character(id, guid, account.id))
      guid = character.object.guid

      assert {:ok, player_pid} = PlayerServer.login(account, self(), guid)
      assert Enum.any?(DynamicSupervisor.which_children(PlayerSupervisor), fn {_, pid, _, _} -> pid == player_pid end)
      assert Entity.pid(guid) == player_pid

      assert %State{
               connection_pid: connection_pid,
               guid: ^guid,
               character: %Character{object: %Object{guid: ^guid}}
             } = :sys.get_state(player_pid)

      assert connection_pid == self()
      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}

      monitor = Process.monitor(player_pid)
      assert :ok = PlayerServer.disconnect(player_pid)
      assert_receive {:DOWN, ^monitor, :process, ^player_pid, :normal}
      assert Entity.pid(guid) == nil
      assert %Character{object: %Object{guid: ^guid}} = CharacterStore.get(character.id)
    end

    test "returns the client to character selection when the owner already exists" do
      {:ok, account} = Account.get_user("test")
      id = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:player, id)
      CharacterStore.put(login_character(id, guid, account.id))

      assert {:ok, player_pid} = PlayerServer.login(account, self(), guid)

      connection = %ConnectionState{account: account}
      message = %Message.CmsgPlayerLogin{character_guid: guid}

      assert ^connection = Message.CmsgPlayerLogin.handle(message, connection)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgCharacterLoginFailed{
                         result: 0x41
                       }}}

      assert :ok = PlayerServer.disconnect(player_pid)
    end
  end

  describe "logout" do
    test "stops the owner before the connection completes logout" do
      {:ok, account} = Account.get_user("test")
      id = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:player, id)
      CharacterStore.put(login_character(id, guid, account.id))

      assert {:ok, player_pid} = PlayerServer.login(account, self(), guid)
      monitor = Process.monitor(player_pid)

      assert :ok = PlayerServer.handle_message(player_pid, %Message.CmsgLogoutRequest{})
      assert_receive {:DOWN, ^monitor, :process, ^player_pid, {:shutdown, :logout}}, 1_500
      assert Entity.pid(guid) == nil

      refute_received {:"$gen_cast", {:write_packet, %Packet{opcode: @smsg_logout_complete}}}
    end
  end

  describe "handle_cast/2 scripted steps" do
    test "runs scripts against the owned character" do
      guid = Guid.from_low_guid(:player, 7)
      state = %State{guid: guid, character: character(guid, level: 10)}
      step = %ScriptStep{command: :add_aura, datalong: 22_888}

      assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:start_script, [step], guid}, state)

      assert [%Effects.TriggerSpell{source_guid: ^guid, target_guid: ^guid, spell_id: 22_888}] =
               state.character.internal.events
    end
  end

  describe "UpdateBatcher.batch/2" do
    test "drains pending update structs into a single packet" do
      player_update = update_object(:player, 1)
      mob_update = update_object(:unit, 2)
      next_player_update = update_object(:player, 3)

      send(self(), {:"$gen_cast", {:send_packet, mob_update}})
      send(self(), {:"$gen_cast", {:send_packet, next_player_update}})

      {packet, updates} = UpdateBatcher.batch(player_update, nil)

      assert object_count(packet) == 3
      assert length(updates) == 3
    end

    test "only drains UpdateObject casts; leaves other messages in the mailbox" do
      send(self(), {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123, payload: <<>>}}})

      {packet, _updates} = UpdateBatcher.batch(update_object(:player, 1), nil)
      assert object_count(packet) == 1

      assert_received {:"$gen_cast", {:send_packet, %Packet{opcode: 0x123}}}
    end

    test "dedupes values blocks for the same guid keeping the newest" do
      stale = update_object(:player, 1, :values)
      fresh = update_object(:player, 1, :values)

      send(self(), {:"$gen_cast", {:send_packet, fresh}})

      {packet, updates} = UpdateBatcher.batch(stale, nil)

      assert object_count(packet) == 1
      assert [%UpdateObject{update_type: :values}] = updates
    end
  end

  describe "handle_cast/2" do
    test "drops source-scoped packets for untracked entities" do
      state = %State{tracked_entities: MapSet.new()}
      packet = %Packet{opcode: 0x123, payload: <<>>}

      assert {:noreply, ^state} =
               PlayerServer.handle_cast({:send_packet, packet, source_guid: 1}, state)
    end

    test "drops destroy packets for untracked entities" do
      state = %State{tracked_entities: MapSet.new()}
      packet = %Message.SmsgDestroyObject{guid: 1}

      assert {:noreply, ^state} = PlayerServer.handle_cast({:send_packet, packet}, state)
      refute_receive {:"$gen_cast", {:write_packet, %Packet{}}}
    end

    test "drops duplicate unscoped create updates" do
      guid = Guid.from_low_guid(:mob, 1, 1)
      state = connection_state(guid)

      assert {:noreply, ^state} =
               PlayerServer.handle_cast({:send_packet, update_object(:unit, guid)}, state)

      refute_receive {:"$gen_cast", {:write_packet, %Packet{}}}
    end

    test "sends source-scoped create refreshes for tracked entities" do
      guid = Guid.from_low_guid(:mob, 1, 1)
      state = connection_state(guid)

      assert {:noreply, %State{tracked_entities: tracked}} =
               PlayerServer.handle_cast(
                 {:send_packet, update_object(:unit, guid), source_guid: guid},
                 state
               )

      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}
      assert MapSet.member?(tracked, guid)
    end

    test "raises when a serialized update object packet reaches the server" do
      state = %State{}
      packet = %Packet{opcode: @smsg_update_object, payload: <<>>}

      assert_raise RuntimeError, "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs", fn ->
        PlayerServer.handle_cast({:send_packet, packet}, state)
      end
    end

    test "sequences acknowledged movement packets at the send boundary" do
      state = %State{connection_pid: self(), guid: 1}
      packet = %Message.SmsgForceMoveUnroot{guid: 1}

      assert {:noreply, %State{movement_counter: 1, pending_movement_acks: %{0 => :unroot}}} =
               PlayerServer.handle_cast({:send_packet, packet}, state)

      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}
    end

    test "initializes instance ownership after a cross-map transfer" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: character(guid, health: 100, max_health: 100),
        ready: true
      }

      destination = WorldRef.instance(389, 12)

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:noreply, %State{ready: false, pending_last_instance_map: nil}} =
               PlayerServer.handle_cast({:start_teleport, -8.23, -43.26, -21.81, 0.0, destination}, state)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTransferPending{map: 389}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgNewWorld{map: 389}}}

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgUpdateInstanceOwnership{player_is_saved_to_a_raid: false}}}

      assert SpatialHash.get_entity(guid) == {guid, destination, -8.23, -43.26, -21.81}
      assert Metadata.query(guid, [:orientation, :world]) == %{orientation: 0.0}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgUpdateLastInstance{}}}
    end

    test "clears city rest when teleporting to a map without loaded navigation data" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

      character =
        %{character(guid, health: 100, max_health: 100) | player: %Player{flags: 0, next_level_xp: 100_000}}
        |> RestLogic.start(:city, 1_000)

      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:noreply, %State{character: teleported}} =
               PlayerServer.handle_cast(
                 {:start_teleport, -11_969.9, -1_646.19, 41.298, 0.0, WorldRef.open(309)},
                 state
               )

      refute RestLogic.resting?(teleported)
      assert teleported.internal.area == 1977
    end

    test "waits for the near teleport acknowledgement before restoring a suspended pet" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      pet_guid = Guid.from_low_guid(:pet, 1863, System.unique_integer([:positive]))
      mob_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))

      character =
        character(guid, health: 100, max_health: 100, summon: pet_guid)
        |> PlayerCombat.mark_attacked(1_000)
        |> PlayerCombat.gain_threat_ref(mob_guid, 1)
        |> then(fn character -> %{character | unit: %{character.unit | target: mob_guid}} end)

      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:noreply, %State{character: %Character{unit: %Unit{summon: 0}} = teleported}} =
               PlayerServer.handle_cast(
                 {:start_teleport, -8_949.95, -132.493, 83.5312, 0.0, WorldRef.open(0)},
                 state
               )

      refute teleported.internal.in_combat
      assert teleported.internal.threat_refs == MapSet.new()
      assert teleported.unit.target == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgMoveTeleportAck{}}}
      assert SpatialHash.get_entity(guid) == {guid, WorldRef.open(0), -8_949.95, -132.493, 83.5312}
      assert Metadata.query(guid, [:orientation, :world]) == %{orientation: 0.0}
      refute_receive :restore_companion
    end

    test "ordinary teleports detach from a transport" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, 164_871)
      character = character(guid, health: 100, max_health: 100)

      movement_block = %{
        character.movement_block
        | movement_flags: 0x02000000,
          transport_guid: transport_guid,
          transport_position: {1.0, 2.0, 3.0, 0.25}
      }

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: %{character | movement_block: movement_block},
        ready: true
      }

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:noreply, %State{character: teleported}} =
               PlayerServer.handle_cast(
                 {:start_teleport, 10.0, 20.0, 30.0, 0.5, WorldRef.open(0)},
                 state
               )

      assert teleported.movement_block.transport_guid == nil
      assert teleported.movement_block.transport_position == nil
      assert Bitwise.band(teleported.movement_block.movement_flags, 0x02000000) == 0
    end

    test "updates the public group leader player flag" do
      character = %{character(1, health: 100, max_health: 100) | player: %Player{flags: 0x20}}
      state = %{character: character}

      assert {:noreply, %{character: leader}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:party_leader_changed, true}, state)

      assert leader.player.flags == 0x21

      assert {:noreply, %{character: member}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:party_leader_changed, false}, %{state | character: leader})

      assert member.player.flags == 0x20
    end

    test "does not broadcast an unchanged group leader player flag" do
      character = %{character(1, health: 100, max_health: 100) | player: %Player{flags: 0x1}}
      state = %{character: character}

      assert {:noreply, ^state} =
               PlayerServer.handle_cast({:party_leader_changed, true}, state)
    end

    test "records the previous instance when returning to the open world" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      character = character(guid, health: 100, max_health: 100)
      character = %{character | internal: %{character.internal | world: WorldRef.instance(389, 12)}}
      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:noreply, %State{ready: false, pending_last_instance_map: 389}} =
               PlayerServer.handle_cast({:start_teleport, 1814.99, -4419.23, -18.81, 1.91, WorldRef.open(1)}, state)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTransferPending{map: 1}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgNewWorld{map: 1}}}

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgUpdateInstanceOwnership{player_is_saved_to_a_raid: false}}}

      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgUpdateLastInstance{}}}
    end

    test "marks player in combat when a mob attack lands" do
      sitting = %{character(1, health: 80, max_health: 100, stand_state: 1) | player: %Player{}}
      state = %{character: sitting}

      assert {:noreply, %{character: character}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_attack, %{caster: 2, damage: 10}}, state)

      assert character.unit.health == 60
      assert character.internal.in_combat == true
      assert is_integer(character.internal.last_hostile_time)
      assert Regen.tick(character, 1_000).unit.health == 60
    end

    test "ignores an attack already in flight during vanish immunity" do
      character = character(1, health: 80, max_health: 100)
      internal = %{character.internal | undetectable_until: Time.now() + 1_000}
      state = %{character: %{character | internal: internal}}

      assert {:noreply, %{character: character}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_attack, %{caster: 2, damage: 10}}, state)

      assert character.unit.health == 80
      refute character.internal.in_combat
    end

    test "ignores an attack already in flight after death" do
      dead = character(1, health: 0, max_health: 100)
      state = %{character: dead}

      assert {:noreply, %{character: ^dead}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_attack, %{caster: 2, damage: 10}}, state)
    end

    test "ignores an attack already in flight after spirit release" do
      ghost = character(1, health: 1, max_health: 100)
      ghost = %{ghost | player: %Player{flags: 0x10}}
      state = %{character: ghost}

      assert {:noreply, %{character: ^ghost}, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_attack, %{caster: 2, damage: 10}}, state)
    end

    test "ignores a harmful spell outcome already in flight after spirit release" do
      ghost = character(1, health: 1, max_health: 100)
      ghost = %{ghost | player: %Player{flags: 0x10}}
      spell = %Spell{id: 133, effects: [%Spell.Effect{type: :school_damage}]}
      state = %{character: ghost}

      assert {:noreply, ^state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_spell_outcome, 2, spell, :resist}, state)
    end

    test "syncs detection metadata before projecting a pending update" do
      guid = System.unique_integer([:positive])
      character = character(guid, health: 80, max_health: 100)

      internal = %{
        character.internal
        | broadcast_update?: true,
          undetectable_until: Time.now() + 1_000
      }

      Metadata.put(guid, %{})
      on_exit(fn -> Metadata.delete(guid) end)

      PlayerServer.maybe_broadcast_update(%State{guid: guid, character: %{character | internal: internal}})

      assert %{undetectable_until: expires_at, stealthed?: false} =
               Metadata.query(guid, [:undetectable_until, :stealthed?])

      assert expires_at > Time.now()
    end

    test "cancels an in-flight cast when the character is dead" do
      guid = System.unique_integer([:positive])
      character = character(guid, health: 0, max_health: 100)
      spell = %Spell{id: 1949, attributes: MapSet.new(), effects: []}
      casting = Cast.new(spell, Target.none(), 1_000)
      character = %{character | internal: %{character.internal | casting: casting}}

      Metadata.put(guid, %{})
      on_exit(fn -> Metadata.delete(guid) end)

      state = PlayerServer.maybe_broadcast_update(%{guid: guid, character: character})

      assert state.character.internal.casting == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{spell: 1949}}}
    end

    test "leaves an in-flight cast alone while the character lives" do
      guid = System.unique_integer([:positive])
      character = character(guid, health: 50, max_health: 100)
      spell = %Spell{id: 1949, attributes: MapSet.new(), effects: []}
      casting = Cast.new(spell, Target.none(), 1_000)
      character = %{character | internal: %{character.internal | casting: casting}}

      Metadata.put(guid, %{})
      on_exit(fn -> Metadata.delete(guid) end)

      state = PlayerServer.maybe_broadcast_update(%{guid: guid, character: character})

      assert state.character.internal.casting == casting
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{}}}, 10
    end
  end

  describe "handle_info/2" do
    test "relocates an attached player from transport-local coordinates" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, 164_871)
      local_position = {2.0, 3.0, 4.0, 0.5}

      character = character(guid, health: 100, max_health: 100)

      character = %{
        character
        | movement_block: %{
            character.movement_block
            | movement_flags: 0x02000000,
              timestamp: 123,
              transport_guid: transport_guid,
              transport_position: local_position
          }
      }

      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}
      ChaseWatch.watch(guid, self(), {0.0, 0.0, 0.0}, 1.0)

      on_exit(fn ->
        ChaseWatch.unwatch(self())
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      transport = %{
        guid: transport_guid,
        entry: 164_871,
        world: WorldRef.open(0),
        position: {10.0, 20.0, 30.0, 1.0}
      }

      assert {:noreply, %State{character: relocated}} =
               PlayerServer.handle_info({:transport_pose, transport}, state)

      expected =
        Transport.passenger_world_position(local_position, transport.position)

      assert_tuple_in_delta(relocated.movement_block.position, expected)
      assert relocated.movement_block.timestamp == 0
      assert {^guid, %WorldRef{map_id: 0}, x, y, z} = SpatialHash.get_entity(guid)
      assert_tuple_in_delta({x, y, z}, Tuple.delete_at(expected, 3))
      assert_receive {:target_moved, ^guid}
    end

    test "worldports with transport attachment preserved across map changes" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, 164_871)
      character = character(guid, health: 100, max_health: 100)

      character = %{
        character
        | movement_block: %{
            character.movement_block
            | movement_flags: 0x02000000,
              timestamp: 123,
              transport_guid: transport_guid,
              transport_position: {1.0, 2.0, 3.0, 0.25}
          }
      }

      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}
      destination = WorldRef.open(1)

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      transport = %{
        guid: transport_guid,
        entry: 164_871,
        world: destination,
        position: {100.0, 200.0, 30.0, 0.75}
      }

      assert {:noreply, %State{ready: false, character: worldported}} =
               PlayerServer.handle_info({:transport_pose, transport}, state)

      assert worldported.internal.world == destination
      assert worldported.movement_block.timestamp == 0
      assert worldported.movement_block.transport_guid == transport_guid
      assert worldported.movement_block.transport_position == {1.0, 2.0, 3.0, 0.25}

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgTransferPending{
                         map: 1,
                         has_transport: true,
                         transport: 164_871,
                         transport_map: 0
                       }}}

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgNewWorld{
                         map: 1,
                         position: %{x: 1.0, y: 2.0, z: 3.0},
                         orientation: 0.25
                       }}}
    end

    test "resurrects a dead passenger before a transport map change" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, 164_871)
      character = %{character(guid, health: 0, max_health: 100) | player: %Player{flags: 0}}

      character = %{
        character
        | movement_block: %{
            character.movement_block
            | movement_flags: 0x02000000,
              transport_guid: transport_guid,
              transport_position: {1.0, 2.0, 3.0, 0.25}
          }
      }

      state = %State{connection_pid: self(), guid: guid, character: character, ready: true}

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      transport = %{
        guid: transport_guid,
        entry: 164_871,
        world: WorldRef.open(1),
        position: {100.0, 200.0, 30.0, 0.75}
      }

      assert {:noreply, %State{character: worldported}} =
               PlayerServer.handle_info({:transport_pose, transport}, state)

      assert worldported.unit.health == 100
      assert worldported.internal.world == WorldRef.open(1)
      assert worldported.movement_block.transport_guid == transport_guid
    end

    test "atomically creates and tracks a pet before completing its attachment" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      pet_guid = Guid.from_low_guid(:pet, 1863, System.unique_integer([:positive]))

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: character(guid, health: 100, max_health: 100),
        tracked_entities: MapSet.new()
      }

      update = update_object(:unit, pet_guid)
      attachment = companion_attachment(pet_guid, update, self())

      assert {:noreply, attached, {:continue, {:finish_companion_attach, ^attachment}}} =
               PlayerServer.handle_info(attachment, state)

      assert attached.character.unit.summon == pet_guid

      assert attached.character.internal.companion ==
               %Companion{
                 kind: :guardian,
                 status: {:active, %EntityRef{guid: pet_guid, entry: 1863, spell_id: 688}}
               }

      assert MapSet.member?(attached.tracked_entities, pet_guid)
      assert %CompanionMonitor{pid: pid, entity_ref: %EntityRef{guid: ^pet_guid}} = attached.companion_monitor
      assert pid == self()
      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: ^pet_guid}}}, 0

      assert {:noreply, completed} =
               PlayerServer.handle_continue({:finish_companion_attach, attachment}, attached)

      assert_receive {:pet_restore_autocast, autocast}
      assert autocast == MapSet.new()
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: ^pet_guid}}}

      assert {:noreply, ^completed} =
               PlayerServer.handle_cast({:send_packet, update}, completed)

      refute_receive {:"$gen_cast", {:write_packet, %Packet{}}}
    end

    test "reuses a pet create already sent by visibility before attachment" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      pet_guid = Guid.from_low_guid(:pet, 1863, System.unique_integer([:positive]))

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: character(guid, health: 100, max_health: 100),
        tracked_entities: MapSet.new()
      }

      update = update_object(:unit, pet_guid)
      attachment = companion_attachment(pet_guid, update, self())

      assert {:noreply, visible} =
               PlayerServer.handle_cast({:send_packet, update}, state)

      assert MapSet.member?(visible.tracked_entities, pet_guid)
      assert_receive {:"$gen_cast", {:write_packet, %Packet{}}}

      assert {:noreply, attached, {:continue, {:finish_companion_attach, ^attachment}}} =
               PlayerServer.handle_info(attachment, visible)

      assert attached.character.unit.summon == pet_guid
      refute_receive {:"$gen_cast", {:write_packet, %Packet{}}}
    end

    test "suspends a hunter pet and clears controls when its process exits" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      pet_guid = Guid.from_low_guid(:pet, 1, System.unique_integer([:positive]))
      pet_pid = spawn(fn -> receive do: (:stop -> :ok) end)

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: character(guid, health: 100, max_health: 100),
        tracked_entities: MapSet.new()
      }

      attachment = %Attachment{
        kind: :hunter_pet,
        entity_ref: %EntityRef{guid: pet_guid, entry: 1, spell_id: 1515},
        pid: pet_pid,
        spells: [],
        create: update_object(:unit, pet_guid)
      }

      {:noreply, attached, _continue} = PlayerServer.handle_info(attachment, state)
      %CompanionMonitor{token: token} = attached.companion_monitor
      Process.exit(pet_pid, :kill)
      assert_receive {:DOWN, ^token, :process, ^pet_pid, :killed} = down

      assert {:noreply, detached, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info(down, attached)

      assert detached.companion_monitor == nil
      assert detached.character.internal.companion == %Companion{kind: :hunter_pet, status: {:suspended, 1, 1515}}
      assert detached.character.unit.summon == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
    end

    test "uses the monitored relationship for charm release" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      controlled_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))

      state = %State{
        connection_pid: self(),
        guid: guid,
        character: character(guid, health: 100, max_health: 100)
      }

      attachment = %Attachment{
        kind: :enslaved,
        entity_ref: %EntityRef{guid: controlled_guid, entry: 1, spell_id: 1098},
        pid: self(),
        spells: []
      }

      assert {:noreply, attached, {:continue, {:finish_companion_attach, ^attachment}}} =
               PlayerServer.handle_info(attachment, state)

      assert attached.character.internal.companion ==
               %Companion{
                 kind: :enslaved,
                 status: {:active, %EntityRef{guid: controlled_guid, entry: 1, spell_id: 1098}}
               }

      assert attached.character.unit.charm == controlled_guid
      assert %CompanionMonitor{entity_ref: %EntityRef{guid: ^controlled_guid}} = attached.companion_monitor

      assert {:noreply, released, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info({:control_released, controlled_guid}, attached)

      assert released.companion_monitor == nil
      assert released.character.internal.companion == Companion.none()
      assert released.character.unit.charm == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
    end
  end

  describe "Network.send_packet/3" do
    test "includes source guid metadata in casts" do
      packet = %Packet{opcode: 0x123, payload: <<>>}

      assert :ok = Network.send_packet(packet, self(), source_guid: 1)

      assert_receive {:"$gen_cast", {:send_packet, ^packet, [source_guid: 1]}}
    end
  end

  defp update_object(:player, guid) do
    update_object(:player, guid, :create_object2)
  end

  defp update_object(:unit, guid) do
    update_object(:unit, guid, :create_object2)
  end

  defp update_object(:player, guid, update_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: :player,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: object(guid),
      unit: unit(),
      player: %Player{
        gender: 1,
        skin: 1,
        face: 1,
        hair_style: 1,
        hair_color: 1,
        coinage: 500
      }
    }
  end

  defp update_object(:unit, guid, update_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: :unit,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: object(guid),
      unit: unit()
    }
  end

  defp character(guid, unit_attrs) do
    {summon, unit_attrs} = Keyword.pop(unit_attrs, :summon)

    character = %Character{
      object: object(guid),
      unit: struct(unit(), unit_attrs),
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    if is_integer(summon) and summon > 0 do
      CompanionLogic.activate(character, :guardian, %EntityRef{
        guid: summon,
        entry: Guid.entry(summon),
        spell_id: 688
      })
    else
      character
    end
  end

  defp login_character(id, guid, account_id) do
    %Character{
      id: id,
      account_id: account_id,
      object: %Object{guid: guid, type: 4, scale_x: 1.0},
      unit: %Unit{
        health: 50,
        max_health: 50,
        power1: 20,
        max_power1: 20,
        level: 1,
        flags: 0,
        race: 1,
        class: 1,
        auras: [],
        strength: 10,
        agility: 10,
        stamina: 10,
        intellect: 10,
        spirit: 10
      },
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, turn_rate: 3.141593},
      internal: %Internal{name: "Owner", area: 0, spells: []}
    }
  end

  defp object(guid) do
    %Object{
      guid: guid,
      type: 1,
      entry: 1001,
      scale_x: 1.0
    }
  end

  defp unit do
    %Unit{
      health: 1000,
      power1: 100,
      max_power1: 100,
      power_type: 0,
      level: 10,
      race: 1,
      class: 1,
      gender: 1,
      spirit: 50
    }
  end

  defp connection_state(tracked_guid) do
    %State{
      connection_pid: self(),
      guid: Guid.from_low_guid(:player, 1),
      tracked_entities: MapSet.new([tracked_guid])
    }
  end

  defp companion_attachment(pet_guid, update, pid) do
    %Attachment{
      kind: :guardian,
      entity_ref: %EntityRef{guid: pet_guid, entry: Guid.entry(pet_guid), spell_id: 688},
      pid: pid,
      spells: [],
      create: update
    }
  end

  defp object_count(%Packet{payload: <<count::little-size(32), 0, _body::binary>>}), do: count

  defp assert_tuple_in_delta(actual, expected) do
    actual
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(expected))
    |> Enum.each(fn {actual_value, expected_value} ->
      assert_in_delta actual_value, expected_value, 0.000001
    end)
  end
end
