defmodule ThistleTea.Game.World.Loader.AlteracGroundVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyGround
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.World.Loader.CreatureScriptRoute
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  @moduletag :vmangos_db

  describe "load_all/1" do
    test "both commanders and all infantry tiers retain complete routes and resolved rally text" do
      :ok = CreatureScriptRoute.load_all(AlteracValleyGround.routes())

      for {entry, count, stop} <- [{13_446, 50, 48}, {13_449, 55, 53}] do
        route = WaypointLoader.context().routes[{:script, entry, 0}]
        assert map_size(route.points) == count
        assert route.pathfind?
        assert [%{command: :talk, texts: [_ | _]}, %{command: :hold_waypoints} = hold] = route.points[2].script_steps
        assert [%{command: :set_home_position}, %{command: :movement}] = route.points[stop].script_steps

        for call <- tl(hold.sub_scripts[1]) do
          assert [%{command: :talk, texts: [_ | _]} | _steps] = call.sub_scripts[1]
        end
      end

      for entry <- 13_524..13_531 do
        route = WaypointLoader.context().routes[{:script, entry, 0}]
        assert map_size(route.points) == if(entry < 13_528, do: 50, else: 55)
      end
    end
  end

  describe "get/1" do
    test "repeatable supply and automatic order quests consume their reference quantities" do
      QuestLoader.load_all()

      for {quest, item} <- [{5_892, 17_522}, {6_985, 17_522}, {5_893, 17_542}, {6_982, 17_542}] do
        assert %Quest{required_items: [{0, ^item, 10}]} = supply = QuestLoader.get(quest)
        assert Quest.repeatable?(supply)
      end

      for {quest, item} <- [{6_846, 17_353}, {6_901, 17_442}] do
        assert %Quest{method: 0, required_items: [{0, ^item, 1}]} = QuestLoader.get(quest)
        template = ItemLoader.get_template(item)
        assert template.max_count == 1
        assert template.area == 2_597
        assert template.duration == 900
      end
    end
  end
end
