defmodule ThistleTea.Game.World.Loader.CreatureScriptRouteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.ScriptWaypoint
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.World.Loader.CreatureScriptRoute

  describe "build/3" do
    test "puts the port's point steps on the creature's script_waypoint path" do
      rows = [
        %ScriptWaypoint{entry: 72, point: 0, position_x: 1.0, waittime: 0},
        %ScriptWaypoint{entry: 72, point: 1, position_x: 2.0, waittime: 0}
      ]

      points = %{1 => [%ScriptStep{command: :talk, dataint: 9}]}
      route = CreatureScriptRoute.build(rows, points, &mark_resolved/1)

      assert %WaypointRoute{first_point: 0, pathfind?: true, points: built} = route
      assert %Waypoint{script_steps: []} = built[0]
      assert %Waypoint{script_steps: [%ScriptStep{command: :talk, texts: [:resolved]}]} = built[1]

      mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 72, 1), entry: 72}}
      step = %ScriptStep{command: :start_waypoints, datalong: 5}

      assert %WaypointRoute{destination_point: 0} =
               Waypoints.resolve(Waypoints.new(%{{:script, 72} => route}), mob, step)
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
