defmodule ThistleTea.Game.World.Loader.GossipVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Network.Message.CmsgGossipHello
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option

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

      alliance_druid = %Character{unit: %Unit{race: 1, class: 11}}
      horde_druid = %Character{unit: %Unit{race: 2, class: 11}}

      assert GossipCondition.met?(alliance_druid, alliance_condition)
      refute GossipCondition.met?(horde_druid, alliance_condition)
      assert GossipCondition.met?(horde_druid, horde_condition)
      refute GossipCondition.met?(alliance_druid, horde_condition)
    end

    test "loads flight-master options and conditional Moonglade greetings" do
      assert :ok = Gossip.load_all()

      assert %Menu{options: options} = Gossip.get_menu(704)
      assert %Option{option_id: 4, text: "I need a ride."} = Enum.find(options, &(&1.id == 0))

      alliance_druid = %Character{unit: %Unit{race: 4, class: 11}}
      horde_druid = %Character{unit: %Unit{race: 6, class: 11}}

      assert %Menu{} = silva_menu = Gossip.get_menu(4041)
      assert CmsgGossipHello.title_text_id(silva_menu, alliance_druid) == 4914
      assert CmsgGossipHello.title_text_id(silva_menu, horde_druid) == 4915

      assert %Menu{} = bunthen_menu = Gossip.get_menu(4042)
      assert CmsgGossipHello.title_text_id(bunthen_menu, alliance_druid) == 4917
      assert CmsgGossipHello.title_text_id(bunthen_menu, horde_druid) == 4918
    end
  end
end
