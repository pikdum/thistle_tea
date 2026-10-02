defmodule ThistleTea.Game.World.Loader.GossipVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Quest.QuestLog.Entry
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.Gossip, as: PlayerGossip
  alias ThistleTea.Game.World.Entity.Player.GossipCondition
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "attaches city guard directions to their gossip options" do
      assert :ok = Gossip.load_all()
      assert %Menu{options: options} = Gossip.menu_for_creature(68)

      assert %Option{action_menu_id: 265, poi: %Gossip.Poi{name: "Stormwind Bank", icon: 6, flags: 99}} =
               Enum.find(options, &(&1.id == 1))
    end

    test "loads class-trainer talent reset options separately from pet trainers" do
      assert :ok = Gossip.load_all()
      assert Gossip.class_trainer?(5515, 3)
      refute Gossip.class_trainer?(5515, 9)
      refute Gossip.class_trainer?(10_090, 3)
      assert %Menu{options: options} = Gossip.menu_for_creature(5515)
      assert %Option{action_menu_id: 4461} = Enum.find(options, &(&1.id == 1))
      assert %Menu{options: options} = Gossip.get_menu(4461)
      assert %Option{option_id: 16, npc_flag: 0x10} = Enum.find(options, &(&1.option_id == 16))
    end

    test "loads hunter pet trainers and their untraining option" do
      assert :ok = Gossip.load_all()
      assert Gossip.pet_trainer?(10_090)
      refute Gossip.pet_trainer?(295)
      assert %Menu{options: options} = Gossip.menu_for_creature(10_090)
      assert %Option{option_id: 17, npc_flag: 0x10} = Enum.find(options, &(&1.option_id == 17))
    end

    test "loads Innkeeper Farley's home-binding option" do
      assert :ok = Gossip.load_all()
      assert %Menu{options: options} = Gossip.menu_for_creature(295)
      assert %Option{option_id: 8, npc_flag: 0x80} = Enum.find(options, &(&1.option_id == 8))
    end

    test "attaches SEND_TAXI_PATH scripts to Moonglade gossip options" do
      assert :ok = Gossip.load_all()

      assert %Menu{options: options} = Gossip.get_menu(4041)

      assert %Option{
               condition: alliance_condition,
               taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 315}]
             } =
               Enum.find(options, &(&1.id == 0))

      assert %Menu{options: options} = Gossip.get_menu(4042)

      assert %Option{
               condition: horde_condition,
               taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 316}]
             } =
               Enum.find(options, &(&1.id == 0))

      alliance_druid = character(1, 11)
      horde_druid = character(2, 11)

      assert GossipCondition.allows?(
               ConditionContext.build(alliance_druid, alliance_condition),
               alliance_condition,
               :deny_unknown
             )

      refute GossipCondition.allows?(
               ConditionContext.build(horde_druid, alliance_condition),
               alliance_condition,
               :deny_unknown
             )

      assert GossipCondition.allows?(
               ConditionContext.build(horde_druid, horde_condition),
               horde_condition,
               :deny_unknown
             )

      refute GossipCondition.allows?(
               ConditionContext.build(alliance_druid, horde_condition),
               horde_condition,
               :deny_unknown
             )
    end

    test "loads flight-master options and conditional Moonglade greetings" do
      assert :ok = Gossip.load_all()

      assert %Menu{options: options} = Gossip.get_menu(704)
      assert %Option{option_id: 4, text: "I need a ride."} = Enum.find(options, &(&1.id == 0))

      alliance_druid = character(4, 11)
      horde_druid = character(6, 11)

      assert %Menu{} = silva_menu = Gossip.get_menu(4041)
      assert PlayerGossip.title_text_id(silva_menu, alliance_druid) == 4914
      assert PlayerGossip.title_text_id(silva_menu, horde_druid) == 4915

      assert %Menu{} = bunthen_menu = Gossip.get_menu(4042)
      assert PlayerGossip.title_text_id(bunthen_menu, alliance_druid) == 4917
      assert PlayerGossip.title_text_id(bunthen_menu, horde_druid) == 4918
    end

    test "loads Olivia Burnside's banker option" do
      assert :ok = Gossip.load_all()

      assert %Menu{menu_id: 699, options: options} = Gossip.menu_for_creature(2455)

      assert %Option{
               id: 0,
               option_id: 9,
               icon: 6,
               text: "I would like to check my deposit box."
             } = Enum.find(options, &(&1.id == 0))
    end

    test "inherits the default battlemaster option when the creature menu has none" do
      assert :ok = Gossip.load_all()

      assert %Menu{menu_id: 6460, options: options} = Gossip.menu_for_creature(14_981)

      assert %Option{
               id: 10,
               option_id: 12,
               npc_flag: 2048,
               icon: 9,
               text: "I wish to join the battle!"
             } = Enum.find(options, &(&1.id == 10))

      assert Bitwise.band(Gossip.npc_flags(14_981), 2048) != 0
    end

    test "keeps the Tamed Kodo's quest-credit script on its greeting" do
      assert :ok = Gossip.load_all()

      assert %Menu{texts: [%Gossip.Text{text_id: 4449, script_steps: steps}]} = Gossip.menu_for_creature(11_627)

      assert [
               %ScriptStep{command: :quest_credit, swap_initial?: true, condition: condition},
               %ScriptStep{command: :remove_aura, datalong: 18_172, swap_initial?: true}
             ] = steps

      refute condition == nil
    end

    test "loads Tharnariun's conditioned replacement-item option" do
      assert :ok = Gossip.load_all()

      assert %Menu{menu_id: 269, options: options} = Gossip.menu_for_creature(3701)

      assert %Option{
               id: 0,
               option_id: 1,
               action_menu_id: -1,
               text: "Tharnariun, I have lost the trap. Could you please give me another?",
               condition: %{entry: 1094, type: :and} = condition,
               action_steps: [%ScriptStep{command: :create_item, datalong: 7586, datalong2: 1}]
             } = Enum.find(options, &(&1.id == 0))

      character = character(1, 1)
      player = %{character.player | quest_log: %{0 => %Entry{quest_id: 2118, status: :incomplete}}}
      character = %{character | player: player}
      context = ConditionContext.build(character, [condition], item_lookup: fn _guid -> nil end)

      assert GossipCondition.allows?(context, condition, :deny_unknown)
    end
  end

  defp character(race, class) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{race: race, class: class, health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
      player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
    }
  end
end
