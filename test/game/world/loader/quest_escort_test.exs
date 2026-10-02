defmodule ThistleTea.Game.World.Loader.QuestEscortTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.ScriptWaypoint
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.World.Loader.QuestEscort, as: QuestEscortLoader

  describe "build/3" do
    test "puts the escort's steps on its script_waypoint path" do
      escort = %QuestEscort{quest_id: 51, entry: 52, credit_point: 2, points: %{1 => [{:say, 9}]}}

      rows = [
        %ScriptWaypoint{entry: 52, point: 1, position_x: 1.0, waittime: 0},
        %ScriptWaypoint{entry: 52, point: 2, position_x: 2.0, waittime: 4_000},
        %ScriptWaypoint{entry: 52, point: 3, position_x: 3.0, waittime: 6_000}
      ]

      {route, start_steps} = QuestEscortLoader.build(escort, rows, &mark_resolved/1)

      assert %WaypointRoute{first_point: 1, pathfind?: true, points: points} = route

      assert %Waypoint{
               position: {1.0, +0.0, +0.0, nil},
               script_steps: [%ScriptStep{command: :talk, texts: [:resolved]}]
             } = points[1]

      assert %Waypoint{wait_time: 4_000, script_steps: [%ScriptStep{command: :quest_explored}]} = points[2]

      assert %Waypoint{
               script_steps: [%ScriptStep{command: :end_map_event}, %ScriptStep{command: :despawn, delay_ms: 6_000}]
             } = points[3]

      assert [%ScriptStep{command: :start_map_event} | _rest] = start_steps
      assert List.last(start_steps).command == :start_waypoints

      mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 52, 1), entry: 52}}
      step = List.last(start_steps)

      assert %WaypointRoute{destination_point: 1, repeat?: false} =
               Waypoints.resolve(Waypoints.new(%{{:escort, 51} => route}), mob, step)
    end

    test "walks the escort's own path in place of its script_waypoint rows" do
      escort = %QuestEscort{
        quest_id: 61,
        entry: 62,
        credit_point: 1,
        path: [{1.0, 2.0, 3.0, 0}, {4.0, 5.0, 6.0, 1_500}]
      }

      {route, [_ | _]} = QuestEscortLoader.build(escort, [], &mark_resolved/1)

      assert %WaypointRoute{first_point: 0, points: points} = route

      assert %Waypoint{
               position: {4.0, 5.0, 6.0, nil},
               wait_time: 1_500,
               script_steps: [%ScriptStep{command: :quest_explored} | _finish]
             } = points[1]
    end
  end

  defp mark_resolved(steps) do
    Enum.map(steps, fn %ScriptStep{} = step ->
      sub_scripts = Map.new(step.sub_scripts, fn {id, sub_steps} -> {id, mark_resolved(sub_steps)} end)
      texts = if step.command == :talk, do: [:resolved], else: step.texts
      %{step | sub_scripts: sub_scripts, texts: texts}
    end)
  end
end
