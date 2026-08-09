defmodule ThistleTea.Game.Player.DevCommandsTest do
  use ExUnit.Case, async: false

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
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.WorldRef

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
                      {:send_packet, %Message.SmsgMessagechat{message: "Instance data (instance_stratholme): 7=2"}}}

      assert {:handled, ^state} = DevCommands.run(state, ".instance data 5")

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgMessagechat{message: "Instance data (instance_stratholme): 5=unsupported"}}}

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

  describe ".go xyz" do
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
