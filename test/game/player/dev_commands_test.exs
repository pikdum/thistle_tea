defmodule ThistleTea.Game.Player.DevCommandsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Honor, as: HonorSystem
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

  describe ".start" do
    test "requires a safe anchor and rejects combat and taxi flight" do
      character = %{debug_character() | unit: %Unit{health: 100, max_health: 100}, player: %Player{}}
      state = %{guid: 1, character: character}

      assert {:handled, ^state} = DevCommands.run(state, ".start")

      assert_received {:"$gen_cast",
                       {:send_packet,
                        %Message.SmsgMessagechat{message: "No safe ground position has been recorded yet."}}}

      anchored = %{state | character: SafePosition.remember(character)}

      for internal <- [
            %{anchored.character.internal | in_combat: true},
            %{anchored.character.internal | taxi_flight: :active}
          ] do
        unavailable = %{anchored | character: %{anchored.character | internal: internal}}
        assert {:handled, ^unavailable} = DevCommands.run(unavailable, ".start")

        assert_received {:"$gen_cast",
                         {:send_packet, %Message.SmsgMessagechat{message: "Stuck recovery is unavailable right now."}}}
      end
    end
  end

  describe ".debug skill" do
    test "sets only known skills within their cap and refreshes defense fields" do
      guid = System.unique_integer([:positive, :monotonic])

      character = %{
        debug_character()
        | id: guid,
          object: %Object{guid: guid},
          unit: %Unit{level: 60, class: 1, agility: 100},
          player: %Player{skills: %{95 => Skills.new_entry(:level, false, 60)}}
      }

      state = %{character: character, ready: false, packed_guid: <<0>>, guid: guid, connection_pid: self()}
      assert {:handled, updated} = DevCommands.run(state, ".debug skill 95 300")
      assert updated.character.player.skills[95].value == 300
      assert updated.character.player.dodge_percentage > 0
      assert CharacterStore.get(guid).player.skills[95].value == 300

      for command <- [".debug skill 95 301", ".debug skill 95 0", ".debug skill 43 100", ".debug skill bad value"] do
        assert {:handled, ^updated} = DevCommands.run(updated, command)
      end
    end
  end

  describe ".debug events" do
    test "parses status and event changes without terminating the player" do
      state = %{guid: 1, character: debug_character()}
      assert {:handled, ^state} = DevCommands.run(state, ".debug events")
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Active events:" <> _}}}

      for action <- ["start", "stop"] do
        assert {:handled, ^state} = DevCommands.run(state, ".debug events  #{action}  999999  ")
        assert_received {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Unknown world event."}}}
      end

      assert {:handled, ^state} = DevCommands.run(state, ".debug events invalid")
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Usage: .debug events" <> _}}}
    end
  end

  describe ".debug honor" do
    test "changes the ledger and owner projection while retaining the earned rank" do
      id = System.unique_integer([:positive, :monotonic])
      guid = Guid.from_low_guid(:player, id)

      character = %{
        debug_character()
        | id: id,
          object: %Object{guid: guid},
          unit: %Unit{level: 60, race: 1},
          player: %Player{}
      }

      state = %{guid: guid, character: character}
      on_exit(fn -> :ets.delete(CharacterStore, id) end)
      assert {:handled, ranked} = DevCommands.run(state, ".debug honor points 20000")
      assert ranked.character.player.honor_rank == 10
      assert ranked.character.player.highest_honor_rank == 10
      assert HonorSystem.snapshot(guid).honor.rank_points == 20_000
      assert CharacterStore.get(id).player.honor_rank == 10

      assert {:handled, demoted} = DevCommands.run(ranked, ".debug honor points 0")
      assert demoted.character.player.honor_rank == 0
      assert demoted.character.player.highest_honor_rank == 10
      assert HonorSystem.snapshot(guid).honor.highest_rank == 10

      for invalid <- ["-1", "65001", "12.5", "no"] do
        assert DevCommands.run(demoted, ".debug honor points #{invalid}") == {:handled, demoted}
        assert HonorSystem.snapshot(guid).honor.rank_points == 0
      end
    end
  end

  describe ".die" do
    test "bypasses shields without spending mana" do
      id = System.unique_integer([:positive, :monotonic])
      guid = Guid.from_low_guid(:player, id)

      holders =
        for {type, spell_id} <- [{:mana_shield, 1463}, {:school_absorb, 11_426}] do
          %Holder{
            spell: %Spell{id: spell_id},
            auras: [%Aura{type: type, amount: 500, misc_value: 127, multiple_value: 2.0}]
          }
        end

      character = %{
        debug_character()
        | id: id,
          object: %Object{guid: guid},
          unit: %Unit{level: 50, health: 100, max_health: 100, power1: 200, max_power1: 200, auras: holders},
          player: %Player{flags: 0}
      }

      state = %{guid: guid, character: character, player_tick_ref: nil}

      on_exit(fn ->
        :ets.delete(CharacterStore, id)
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end)

      assert {:handled, updated} = DevCommands.run(state, ".die")
      assert updated.character.unit.health == 0
      assert updated.character.unit.power1 == 200
      assert updated.character.unit.auras == []
      assert updated.character.internal.death_finalized?
    end
  end

  describe ".mail" do
    test "posts an immediate letter to an offline character" do
      id = System.unique_integer([:positive, :monotonic])
      name = "Mailtest#{id}"
      recipient_guid = Guid.from_low_guid(:player, id)

      recipient = %Character{
        id: id,
        account_id: id,
        object: %Object{guid: recipient_guid},
        internal: %Internal{name: name}
      }

      CharacterStore.put(recipient)
      on_exit(fn -> :ets.delete(CharacterStore, id) end)

      sender_guid = Guid.from_low_guid(:player, id + 1)
      state = %{guid: sender_guid}

      assert {:handled, ^state} = DevCommands.run(state, ".mail #{name} hello from a debug command")
      assert {token, [mail]} = PostOffice.open(recipient_guid)

      assert mail.sender == sender_guid
      assert mail.receiver == recipient_guid
      assert mail.subject == "Debug mail"
      assert mail.body == "hello from a debug command"
      assert mail.deliver_at <= System.monotonic_time(:millisecond)

      PostOffice.acknowledge(recipient_guid, token, [mail.id])
      assert :ok = PostOffice.close(recipient_guid, token, [])
    end

    test "rejects a missing message" do
      state = %{guid: Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))}

      assert {:handled, ^state} = DevCommands.run(state, ".mail Nobody")
    end
  end

  describe ".debug transport" do
    test "shows and advances the attached transport" do
      entry = System.unique_integer([:positive, :monotonic])
      route = TransportLogic.build_ship(entry, "Debug Ship", 10, ship_nodes(), 10, 1, 20_000)
      entity = GameObject.build_transport(transport_template(entry), TransportLogic.pose_at(route, 0))
      {:ok, pid} = TransportServer.start_link({entity, route, schedule: false, clock: fn -> 1_000 end})
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      player_guid = Guid.from_low_guid(:player, entry)

      character = %Character{
        object: %Object{guid: player_guid},
        movement_block: %MovementBlock{
          position: {-10.0, 0.0, 0.0, 0.0},
          transport_guid: entity.object.guid
        },
        internal: %Internal{world: WorldRef.open(0)}
      }

      state = %{guid: player_guid, character: character}

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: status_message}}}

      assert status_message =~ "Debug Ship entry #{entry}"
      assert status_message =~ "0ms/20000ms"

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport advance 3 #{entry}")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Advanced transport " <> advance_message}}}

      assert advance_message == "#{entry} by 3s."

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: advanced_status}}}

      assert advanced_status =~ "3000ms/20000ms"
      assert Transports.get(entity.object.guid).progress_ms == 3_000
    end

    test "reports invalid schedule advancement" do
      state = %{guid: 1, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".debug transport advance tomorrow")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: message}}}

      assert message =~ "Invalid command"
    end
  end

  describe ".debug taxi" do
    test "unlocks the loaded flight network" do
      id = System.unique_integer([:positive, :monotonic])
      previous_network = TaxiLoader.get()

      network =
        Network.build(
          [
            %Node{
              id: 2,
              map_id: 0,
              position: {0.0, 0.0, 0.0},
              name: "Debug",
              mount_display_ids: %{alliance: 6852}
            }
          ],
          [],
          %{},
          []
        )

      :ets.insert(TaxiLoader, {:network, network})

      character = %Character{
        id: id,
        object: %Object{guid: Guid.from_low_guid(:player, id)},
        player: %Player{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      state = %{guid: character.object.guid, character: character}

      on_exit(fn ->
        :ets.delete(CharacterStore, id)

        if previous_network do
          :ets.insert(TaxiLoader, {:network, previous_network})
        else
          :ets.delete(TaxiLoader, :network)
        end
      end)

      assert {:handled, state} = DevCommands.run(state, ".debug taxi")
      assert state.character.player.taxi_nodes == MapSet.new([2])
      assert CharacterStore.get(id).player.taxi_nodes == MapSet.new([2])
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "All flight paths unlocked."}}}
    end
  end

  describe ".debug reputation" do
    test "finds, sets, and reports faction standing" do
      id = System.unique_integer([:positive, :monotonic])
      guid = Guid.from_low_guid(:player, id)
      previous_catalog = ReputationLoader.catalog()

      definition = %Definition{
        id: 72,
        index: 19,
        name: "Stormwind",
        variants: [%Variant{race_mask: 1, base_standing: 0, flags: 0x01}]
      }

      catalog = %Catalog{factions: %{72 => definition}}
      ReputationLoader.put_catalog(catalog)

      character = %Character{
        id: id,
        object: %Object{guid: guid},
        unit: %Unit{race: 1, class: 1, level: 60, auras: []},
        player: %Player{reputation: ReputationLogic.initialize(catalog, 1, 1)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      state = %{guid: guid, character: character}

      on_exit(fn ->
        ReputationLoader.put_catalog(previous_catalog)
        :ets.delete(CharacterStore, id)
        Metadata.delete(guid)
      end)

      assert {:handled, state} = DevCommands.run(state, ".debug reputation set 72 9000")
      assert PlayerReputation.standing(state.character, 72) == 9_000

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Stormwind (72), slot 19: 9000, Honored" <> _}}}

      assert {:handled, ^state} = DevCommands.run(state, ".debug reputation find storm")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Stormwind (72), slot 19"}}}
    end
  end

  describe ".instance data" do
    test "reports registered data without exposing a write path" do
      world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      state = %{guid: 1, character: %{debug_character() | internal: %Internal{world: world}}}

      InstanceData.publish(%Copy{
        world: world,
        owner: {:player, 1},
        script_name: "instance_stratholme",
        data: %{7 => 2}
      })

      on_exit(fn -> InstanceData.remove(world) end)

      assert {:handled, ^state} = DevCommands.run(state, ".instance data")

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgMessagechat{
                         message: "Instance data (instance_stratholme): 0=0, 1=0, 2=0, 3=0, 4=0, 5=0, 6=0, 7=2, 8=0"
                       }}}

      assert {:handled, ^state} = DevCommands.run(state, ".instance data 5")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Instance data (instance_stratholme): 5=0"}}}

      assert {:handled, ^state} = DevCommands.run(state, ".instance data 7 2")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Invalid command. Use: .instance data [field]"}}}

      assert InstanceData.read(world, [7]).fields == %{7 => {:ok, 2}}
    end

    test "distinguishes open worlds from destroyed copies" do
      open_state = %{guid: 1, character: debug_character()}
      missing_world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      missing_state = %{guid: 1, character: %{debug_character() | internal: %Internal{world: missing_world}}}

      assert {:handled, ^open_state} = DevCommands.run(open_state, ".instance data 7")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Current world is not an instance copy."}}}

      assert {:handled, ^missing_state} = DevCommands.run(missing_state, ".instance data")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Instance copy is no longer active."}}}
    end
  end

  describe ".debug position" do
    test "reports open-world and instance positions with orientation" do
      open_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))
      instance_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive, :monotonic]))
      instance = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      state = %{guid: 1, character: debug_character()}

      SpatialHash.insert(:mobs, open_guid, WorldRef.open(0), 1.0, 2.0, 3.0)
      SpatialHash.insert(:mobs, instance_guid, instance, 4032.73, -3366.51, 115.063)
      Metadata.put(open_guid, %{orientation: 0.0})
      Metadata.put(instance_guid, %{orientation: 5.42797})

      on_exit(fn ->
        SpatialHash.remove(:mobs, open_guid)
        SpatialHash.remove(:mobs, instance_guid)
        Metadata.delete(open_guid)
        Metadata.delete(instance_guid)
      end)

      assert {:handled, ^state} = DevCommands.run(state, ".debug position #{open_guid}")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: open_message}}}

      assert open_message ==
               "Entity #{open_guid}: map 0 / open, position 1.0 2.0 3.0, orientation 0.0"

      assert {:handled, ^state} = DevCommands.run(state, ".debug position #{instance_guid}")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: message}}}

      assert message ==
               "Entity #{instance_guid}: map 329 / instance #{instance.instance_id}, position 4032.73 -3366.51 115.063, orientation 5.42797"
    end

    test "reports missing entities and rejects malformed guids" do
      state = %{guid: 1, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".debug position 999999")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Entity 999999 is inactive or missing."}}}

      assert {:handled, ^state} = DevCommands.run(state, ".debug position nope")

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{message: "Invalid command. Use: .debug position <guid>"}}}
    end
  end

  describe ".go xyz" do
    test "rejects malformed coordinates without teleporting" do
      state = %{guid: 1, character: debug_character()}

      for args <- ["", "1", "1 2", "1 2 3 0 extra", "bad 2 3", "1 2m 3", "1 2 3m", "1 2 3 -1", "1 2 3 0x"] do
        assert {:handled, ^state} = DevCommands.run(state, ".go xyz " <> args)

        assert_received {:"$gen_cast",
                         {:send_packet,
                          %Message.SmsgMessagechat{message: "Invalid command. Use: .go xyz <x> <y> <z> [map]"}}}
      end

      refute_received {:"$gen_cast", {:start_teleport, _, _, _, _}}
    end

    test "accepts complete coordinates with an explicit map" do
      state = %{guid: 1, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".go xyz 16342 16279 69.44 451")
      assert_receive {:"$gen_cast", {:start_teleport, 16_342.0, 16_279.0, 69.44, 451}}
    end

    test "preserves the current instance copy when no map is supplied" do
      world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
      character = %{debug_character() | internal: %Internal{world: world}}
      state = %{guid: 1, character: character}

      assert {:handled, ^state} = DevCommands.run(state, ".go xyz 3680.53 -3643.80 140.03")

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: message}}}
      assert message == "Teleporting to 3680.53, -3643.8, 140.03 on map 329 / instance #{world.instance_id}"

      assert_receive {:"$gen_cast", {:start_teleport, 3680.53, -3643.8, 140.03, ^world}}
    end
  end

  describe ".battleground" do
    test "reports status through the full command and VMangos-style alias" do
      guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      state = %{guid: guid, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".battleground info")
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Battleground: none."}}}

      assert {:handled, ^state} = DevCommands.run(state, ".bg info")
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "Battleground: none."}}}
    end

    test "shows usage for unsupported subcommands" do
      state = %{guid: 1, character: debug_character()}

      assert {:handled, ^state} = DevCommands.run(state, ".battleground score alliance")

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgMessagechat{
                         message:
                           "Invalid command. Use: .battleground <join|list> [warsong|arathi|alterac], start, info, or leave"
                       }}}
    end
  end

  defp debug_character do
    %Character{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp transport_template(entry) do
    %GameObjectTemplate{
      entry: entry,
      type: 15,
      display_id: 3015,
      name: "Debug Ship",
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [10, 10, 1] ++ List.duplicate(0, 21)
    }
  end

  defp ship_nodes do
    [
      transport_node(0, {-10.0, 0.0, 0.0}, 0, 0),
      transport_node(1, {0.0, 0.0, 0.0}, 2, 2),
      transport_node(2, {10.0, 0.0, 0.0}, 0, 0),
      transport_node(3, {20.0, 0.0, 0.0}, 2, 2),
      transport_node(4, {10.0, 0.0, 0.0}, 0, 0),
      transport_node(5, {0.0, 0.0, 0.0}, 2, 2)
    ]
  end

  defp transport_node(index, position, flags, delay) do
    %{node_index: index, map_id: 0, position: position, flags: flags, delay: delay}
  end
end
