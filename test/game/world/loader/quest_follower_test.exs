defmodule ThistleTea.Game.World.Loader.QuestFollowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest.QuestFollower
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.QuestFollower, as: QuestFollowerLoader

  describe "gossip_option/2" do
    test "starts the follower from a closing gossip option offered while the quest is incomplete" do
      follower = %QuestFollower{quest_id: 2078, entry: 6669, goal: {6667, 10}, gossip: "[PH] Insert key"}

      assert %Option{
               icon: 0,
               text: "[PH] Insert key",
               option_id: 1,
               npc_flag: 0,
               action_menu_id: -1,
               talk_credit?: false,
               condition: %Condition{type: :quest_taken, value1: 2078, value2: 1},
               action_steps: [%ScriptStep{command: :start_map_event, datalong: 2078} | _rest]
             } = QuestFollowerLoader.gossip_option(follower, & &1)
    end
  end
end
