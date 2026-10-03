defmodule ThistleTea.Game.World.Loader.QuestFollowerVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestFollower
  alias ThistleTea.Game.Core.Quest.QuestFollower.Catalog
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.QuestFollower, as: QuestFollowerLoader

  @moduletag :vmangos_db

  setup do
    QuestLoader.init()
    QuestLoader.load_all()
    GossipLoader.init()
    QuestFollowerLoader.load_all()
    :ok
  end

  describe "load_all/1" do
    test "starts every quest-accept follower from its exploration quest with every line resolved" do
      for %QuestFollower{gossip: nil} = follower <- Catalog.all() do
        assert %Quest{special_flags: flags, start_script_steps: steps} = QuestLoader.get(follower.quest_id)
        assert Bitwise.band(flags, 2) == 2

        assert %ScriptStep{} =
                 Enum.find(
                   steps,
                   &match?(%ScriptStep{command: :start_map_event, datalong: id} when id == follower.quest_id, &1)
                 )

        for %ScriptStep{command: :talk} = talk <- flatten(steps) do
          assert [_ | _] = talk.texts, "quest #{follower.quest_id} text #{talk.dataint} is missing"
        end
      end
    end

    test "offers every gossip follower's start on its creature with every line resolved" do
      for %QuestFollower{gossip: text} = follower when is_binary(text) <- Catalog.all() do
        assert %Menu{options: options} = GossipLoader.menu_for_creature(follower.entry)
        assert %Option{action_steps: steps} = Enum.find(options, &(&1.text == text))
        assert %ScriptStep{command: :start_map_event} = hd(steps)

        for %ScriptStep{command: :talk} = talk <- flatten(steps) do
          assert [_ | _] = talk.texts, "quest #{follower.quest_id} text #{talk.dataint} is missing"
        end
      end
    end
  end

  defp flatten(steps) do
    Enum.flat_map(steps, fn %ScriptStep{} = step ->
      [step | step.sub_scripts |> Map.values() |> Enum.flat_map(&flatten/1)]
    end)
  end
end
