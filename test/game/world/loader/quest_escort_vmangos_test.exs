defmodule ThistleTea.Game.World.Loader.QuestEscortVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.Core.Quest.QuestEscort.Catalog
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.QuestEscort, as: QuestEscortLoader
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  @moduletag :vmangos_db

  setup do
    WaypointLoader.init()
    WaypointLoader.load_all()
    QuestLoader.init()
    QuestLoader.load_all()
    QuestEscortLoader.load_all()
    :ok
  end

  describe "load_all/1" do
    test "gives every ported escort a path and an exploration quest to start it" do
      context = WaypointLoader.context()

      for %QuestEscort{} = escort <- Catalog.all() do
        assert %WaypointRoute{points: points} = route(context, escort)
        assert is_nil(escort.credit_point) or Map.has_key?(points, escort.credit_point)
        assert %Quest{special_flags: flags, start_script_steps: steps} = QuestLoader.get(escort.quest_id)
        assert Bitwise.band(flags, 2) == 2

        assert Enum.any?(
                 flatten(steps),
                 &match?(%ScriptStep{command: :start_map_event, datalong: id} when id == escort.quest_id, &1)
               )
      end
    end

    test "resolves every escort's speech to broadcast texts" do
      context = WaypointLoader.context()

      for %QuestEscort{} = escort <- Catalog.all() do
        %WaypointRoute{points: points} = route(context, escort)
        %Quest{start_script_steps: start_steps} = QuestLoader.get(escort.quest_id)

        steps = Enum.flat_map(points, fn {_point, waypoint} -> waypoint.script_steps end) ++ start_steps

        for %ScriptStep{command: :talk} = talk <- flatten(steps) do
          assert [_ | _] = talk.texts, "quest #{escort.quest_id} text #{talk.dataint} is missing"
        end
      end
    end

    test "walks Volcor's two quests along their own paths" do
      context = WaypointLoader.context()

      assert %WaypointRoute{first_point: 1} = route(context, Catalog.get(994))
      assert %WaypointRoute{first_point: 0, points: points} = route(context, Catalog.get(995))
      assert map_size(points) == 5
    end

    test "resolves Miran's ambush texts and keeps Ruul's cage script" do
      %WaypointRoute{points: points} = route(WaypointLoader.context(), Catalog.get(309))

      assert [%ScriptStep{command: :talk, texts: [%{text: "Help! I've only one hand" <> _}]}, raider, _raider] =
               points[19].script_steps

      assert [%ScriptStep{texts: [%{text: "Feel the power of the Dark Iron Dwarves!"}]}] =
               Map.fetch!(raider.sub_scripts, raider.dataint2)

      assert [%ScriptStep{command: :open_door} | _rest] = QuestLoader.get(6482).start_script_steps
    end
  end

  defp route(context, %QuestEscort{} = escort) do
    mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, escort.entry, 1), entry: escort.entry}}

    start = %ScriptStep{
      command: :start_waypoints,
      datalong: QuestEscort.waypoint_source(),
      dataint3: escort.quest_id
    }

    Waypoints.resolve(context, mob, start)
  end

  defp flatten(steps) do
    Enum.flat_map(steps, fn %ScriptStep{} = step ->
      [step | step.sub_scripts |> Map.values() |> Enum.flat_map(&flatten/1)]
    end)
  end
end
