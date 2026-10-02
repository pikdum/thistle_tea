defmodule ThistleTea.Game.World.Entity.Player.GossipTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Gossip
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Test.Unique

  describe "send_menu/4" do
    test "starts the shown greeting's script on its speaker" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 11_627, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)

      steps = [%ScriptStep{command: :quest_credit, swap_initial?: true}]
      menu = %Menu{menu_id: 3650, texts: [%Text{text_id: 4449, condition_id: 0, script_steps: steps}]}

      Gossip.send_menu(creature_guid, menu, [], %{character: character(player_guid)})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{title_text_id: 4449}}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, ^player_guid}}
    end

    test "starts nothing for a greeting without a script" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 68, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)

      menu = %Menu{menu_id: 1, texts: [%Text{text_id: 2, condition_id: 0}]}

      Gossip.send_menu(creature_guid, menu, [], %{character: character(player_guid)})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{title_text_id: 2}}}
      refute_receive {:"$gen_cast", {:start_script, _steps, _target}}, 50
    end
  end

  defp character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
      player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }
  end
end
