defmodule ThistleTea.Game.Network.Message.CmsgGossipSelectOptionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgGossipSelectOption
  alias ThistleTea.Game.Network.Message.SmsgGossipComplete
  alias ThistleTea.Game.Network.Message.SmsgShowBank
  alias ThistleTea.Game.Network.Message.SmsgShowtaxinodes
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "handle/2" do
    test "dispatches a taxi gossip script to the player owner" do
      player_guid = System.unique_integer([:positive, :monotonic])
      {:ok, _owner} = Entity.register(player_guid)

      option = %Option{
        id: 0,
        option_id: 1,
        action_menu_id: -1,
        taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 315}]
      }

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
        player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
      }

      state = %{character: character, gossip_menu_options: [option]}
      message = %CmsgGossipSelectOption{guid: 1, gossip_list_id: 0}

      assert %{gossip_menu_options: []} = CmsgGossipSelectOption.handle(message, state)
      assert_receive {:send_taxi_path, 315}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
    end

    test "opens the flight map for a taxi-vendor option" do
      previous_network = TaxiLoader.get()
      player_id = System.unique_integer([:positive, :monotonic])
      player_guid = Guid.from_low_guid(:player, player_id)
      flightmaster_guid = Guid.from_low_guid(:mob, 352, System.unique_integer([:positive, :monotonic]))

      network =
        Network.build(
          [
            %Node{
              id: 2,
              map_id: 0,
              position: {2.0, 0.0, 0.0},
              name: "Stormwind",
              mount_display_ids: %{alliance: 6852}
            }
          ],
          [],
          %{},
          []
        )

      :ets.insert(TaxiLoader, {:network, network})
      Metadata.put(flightmaster_guid, %{npc_flags: 0x8, alive?: true})
      SpatialHash.update(:mobs, flightmaster_guid, WorldRef.open(0), 2.0, 0.0, 0.0)

      on_exit(fn ->
        Metadata.delete(flightmaster_guid)
        SpatialHash.remove(:mobs, flightmaster_guid)

        if previous_network do
          :ets.insert(TaxiLoader, {:network, previous_network})
        else
          :ets.delete(TaxiLoader, :network)
        end
      end)

      character = %Character{
        id: player_id,
        object: %Object{guid: player_guid},
        unit: %Unit{race: 1},
        player: %Player{
          taxi_nodes: MapSet.new([2]),
          skills: %{},
          quest_log: %{},
          rewarded_quests: MapSet.new(),
          reputation: %Reputation{}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      option = %Option{id: 0, option_id: 4}
      state = %{character: character, gossip_menu_options: [option]}
      message = %CmsgGossipSelectOption{guid: flightmaster_guid, gossip_list_id: 0}

      assert CmsgGossipSelectOption.handle(message, state) == state

      assert_receive {:"$gen_cast", {:send_packet, %SmsgShowtaxinodes{guid: ^flightmaster_guid, nearest_node: 2}}}
    end

    test "opens the bank for a banker option" do
      player_id = System.unique_integer([:positive, :monotonic])
      player_guid = Guid.from_low_guid(:player, player_id)
      banker_guid = Guid.from_low_guid(:mob, 54, System.unique_integer([:positive, :monotonic]))
      {:ok, _owner} = Entity.register(player_guid)

      Metadata.put(banker_guid, %{npc_flags: 0x00000100, alive?: true})
      SpatialHash.update(:mobs, banker_guid, WorldRef.open(0), 2.0, 0.0, 0.0)

      on_exit(fn ->
        Metadata.delete(banker_guid)
        SpatialHash.remove(:mobs, banker_guid)
      end)

      character = %Character{
        id: player_id,
        object: %Object{guid: player_guid},
        unit: %Unit{health: 100, max_health: 100},
        player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      option = %Option{id: 0, option_id: 9}
      state = %State{ready: true, guid: player_guid, character: character, gossip_menu_options: [option]}
      message = %CmsgGossipSelectOption{guid: banker_guid, gossip_list_id: 0}

      assert %State{active_banker_guid: ^banker_guid} = CmsgGossipSelectOption.handle(message, state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgShowBank{banker_guid: ^banker_guid}}}
    end

    test "revalidates a conditioned option after player state changes" do
      option = %Option{
        id: 0,
        option_id: 1,
        condition: %Condition{entry: 1, type: :level, value1: 10, value2: 1},
        taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 315}]
      }

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          level: 9,
          race: 1,
          class: 1,
          health: 100,
          max_health: 100,
          power1: 0,
          max_power1: 0,
          auras: []
        },
        player: %Player{
          skills: %{},
          quest_log: %{},
          rewarded_quests: MapSet.new(),
          reputation: %Reputation{}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
      }

      state = %{character: character, gossip_menu_options: [option]}
      message = %CmsgGossipSelectOption{guid: 2, gossip_list_id: 0}

      assert CmsgGossipSelectOption.handle(message, state) == state
      refute_receive {:send_taxi_path, 315}
      refute_receive {:"$gen_cast", {:send_packet, _packet}}
    end
  end
end
