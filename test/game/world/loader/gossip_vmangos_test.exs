defmodule ThistleTea.Game.World.Loader.GossipVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Gossip, as: PlayerGossip
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  describe "load_all/0" do
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
