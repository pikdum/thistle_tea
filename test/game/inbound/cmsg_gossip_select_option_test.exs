defmodule ThistleTea.Game.Inbound.CmsgGossipSelectOptionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects.SendTaxiPath
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.Travel.Taxi.Network
  alias ThistleTea.Game.Core.Travel.Taxi.Node
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgGossipSelectOption
  alias ThistleTea.Game.Network.Message.SmsgGossipComplete
  alias ThistleTea.Game.Network.Message.SmsgGossipPoi
  alias ThistleTea.Game.Network.Message.SmsgQuestupdateAddKill
  alias ThistleTea.Game.Network.Message.SmsgShowBank
  alias ThistleTea.Game.Network.Message.SmsgShowtaxinodes
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Gossip.Poi
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  describe "handle/2" do
    test "dispatches a taxi gossip script to the player owner" do
      player_guid = Unique.integer()
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

      state = %{character: character, gossip_menu_options: [option], gossip_menu_guid: 1}
      message = %CmsgGossipSelectOption{guid: 1, gossip_list_id: 0}

      assert %{gossip_menu_options: []} = Inbound.handle(message, state)
      assert_receive %SendTaxiPath{path_id: 315}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
    end

    test "closes gossip and runs a replacement-item script on the source creature" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 3701, Unique.integer())
      {:ok, _player_owner} = Entity.register(player_guid)
      {:ok, _creature_owner} = Entity.register(creature_guid)

      steps = [%ScriptStep{command: :create_item, datalong: 7586, datalong2: 1}]

      option = %Option{
        id: 0,
        option_id: 1,
        action_menu_id: -1,
        action_steps: steps
      }

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
        player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
      }

      state = %{character: character, gossip_menu_options: [option], gossip_menu_guid: creature_guid}
      message = %CmsgGossipSelectOption{guid: creature_guid, gossip_list_id: 0}

      assert %{gossip_menu_options: []} = Inbound.handle(message, state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, ^player_guid}}
    end

    test "opens the flight map for a taxi-vendor option" do
      previous_network = TaxiLoader.get()
      player_id = Unique.integer()
      player_guid = Guid.from_low_guid(:player, player_id)
      flightmaster_guid = Guid.from_low_guid(:mob, 352, Unique.integer())

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
      state = %{character: character, gossip_menu_options: [option], gossip_menu_guid: flightmaster_guid}
      message = %CmsgGossipSelectOption{guid: flightmaster_guid, gossip_list_id: 0}

      assert Inbound.handle(message, state) == state

      assert_receive {:"$gen_cast", {:send_packet, %SmsgShowtaxinodes{guid: ^flightmaster_guid, nearest_node: 2}}}
    end

    test "opens the bank for a banker option" do
      player_id = Unique.integer()
      player_guid = Guid.from_low_guid(:player, player_id)
      banker_guid = Guid.from_low_guid(:mob, 54, Unique.integer())
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

      state = %State{
        ready: true,
        guid: player_guid,
        character: character,
        gossip_menu_options: [option],
        gossip_menu_guid: banker_guid
      }

      message = %CmsgGossipSelectOption{guid: banker_guid, gossip_list_id: 0}

      assert %State{active_banker_guid: ^banker_guid} = Inbound.handle(message, state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgShowBank{banker_guid: ^banker_guid}}}
    end

    test "marks a guard's directions on the map and keeps the menu open" do
      poi = %Poi{x: -8885.39, y: 640.052, icon: 6, flags: 99, data: 0, name: "Stormwind Bank"}
      option = %Option{id: 0, option_id: 1, action_menu_id: 0, poi: poi}
      character = talker(Guid.from_low_guid(:player, Unique.integer()), %{})
      guard_guid = Guid.from_low_guid(:mob, 68, Unique.integer())
      state = %{character: character, gossip_menu_options: [option], gossip_menu_guid: guard_guid}

      assert Inbound.handle(%CmsgGossipSelectOption{guid: guard_guid, gossip_list_id: 0}, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipPoi{name: "Stormwind Bank", icon: 6, flags: 99}}}
      refute_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
    end

    test "credits talk objectives when an option closes creature gossip" do
      entry = 900_000 + Unique.integer()
      quest = %Quest{id: entry, required_kills: [{0, entry, 1}]}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      on_exit(fn -> :ets.delete(QuestLoader, {:quest, quest.id}) end)

      {:ok, log} = QuestLog.add(%{}, quest.id)
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      npc_guid = Guid.from_low_guid(:mob, entry, Unique.integer())
      option = %Option{id: 0, option_id: 1, action_menu_id: -1}

      state = %State{
        guid: player_guid,
        character: talker(player_guid, log),
        gossip_menu_options: [option],
        gossip_menu_guid: npc_guid
      }

      state = Inbound.handle(%CmsgGossipSelectOption{guid: npc_guid, gossip_list_id: 0}, state)

      assert QuestLog.get(state.character.player.quest_log, quest.id).counts == %{0 => 1}
      quest_id = quest.id

      assert_receive {:"$gen_cast",
                      {:send_packet, %SmsgQuestupdateAddKill{quest_id: ^quest_id, victim_guid: ^npc_guid}}}
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

      state = %{character: character, gossip_menu_options: [option], gossip_menu_guid: 2}
      message = %CmsgGossipSelectOption{guid: 2, gossip_list_id: 0}

      assert Inbound.handle(message, state) == state
      refute_receive %SendTaxiPath{path_id: 315}
      refute_receive {:"$gen_cast", {:send_packet, _packet}}
    end
  end

  defp talker(guid, quest_log) do
    %Character{
      id: Guid.low_guid(guid),
      object: %Object{guid: guid},
      unit: %Unit{level: 10, race: 1, class: 1, health: 100, max_health: 100, auras: []},
      player: %Player{skills: %{}, quest_log: quest_log, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }
  end
end
