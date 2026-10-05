defmodule ThistleTea.Game.World.Loader.AlteracCavalryVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyCavalry
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.World.Loader.CreatureScriptRoute
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  @moduletag :vmangos_db

  describe "load_all/1" do
    test "both complete commander routes include resolved rally speech and formation joins" do
      :ok = CreatureScriptRoute.load_all(AlteracValleyCavalry.routes())

      for {entry, rally, last} <- [{13_441, 2, 82}, {13_577, 5, 92}] do
        route = WaypointLoader.context().routes[{:script, entry, 0}]
        assert map_size(route.points) == last + 1
        assert route.pathfind?

        assert [%{command: :talk, texts: [_ | _]}, %{command: :hold_waypoints} = pause] =
                 route.points[rally].script_steps

        [call] = pause.sub_scripts[1]

        assert [
                 %{command: :talk, texts: [_ | _]},
                 %{command: :set_run},
                 %{command: :set_phase},
                 %{command: :leave_creature_group},
                 %{formation_from_position?: true}
               ] =
                 call.sub_scripts[1]
      end

      for {entry, count} <- [{13_440, 81}, {13_576, 93}] do
        assert map_size(WaypointLoader.context().routes[{:script, entry, 0}].points) == count
      end
    end
  end

  describe "get/1" do
    test "stable returns are exploration quests and hide turn-ins consume one enemy hide" do
      QuestLoader.init()
      QuestLoader.load_all()

      for {tame, item, hide, hide_item} <- [{7_001, 17_626, 7_002, 17_642}, {7_027, 17_689, 7_026, 17_643}] do
        assert %Quest{src_item_id: ^item} = quest = QuestLoader.get(tame)
        assert Quest.repeatable?(quest)
        assert Quest.exploration?(quest)
        assert %Quest{required_items: [{0, ^hide_item, 1}]} = QuestLoader.get(hide)
      end
    end
  end
end
