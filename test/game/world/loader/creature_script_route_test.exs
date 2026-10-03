defmodule ThistleTea.Game.World.Loader.CreatureScriptRouteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.ScriptWaypoint
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
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
               Waypoints.resolve(Waypoints.new(%{{:script, 72, 0} => route}), mob, step)
    end
  end

  describe "route_rows/2" do
    test "numbers a port's own path from zero" do
      route = %Route{entry: 72, variant: 3, path: [{1.0, 2.0, 3.0, 0}, {4.0, 5.0, 6.0, 500}]}

      assert [
               %ScriptWaypoint{entry: 72, point: 0, position_x: 1.0, waittime: 0},
               %ScriptWaypoint{entry: 72, point: 1, position_z: 6.0, waittime: 500}
             ] = CreatureScriptRoute.route_rows(route, [])
    end

    test "keeps the script_waypoint rows of a route without its own path" do
      rows = [%ScriptWaypoint{entry: 72, point: 0}]
      assert CreatureScriptRoute.route_rows(%Route{entry: 72}, rows) == rows
    end
  end

  describe "Route.key/1" do
    test "start_waypoints source 5 picks a variant by dataint3" do
      rows = [%ScriptWaypoint{entry: 72, point: 0, position_x: 9.0, waittime: 0}]
      route = CreatureScriptRoute.build(rows, %{}, &mark_resolved/1)
      routes = Waypoints.new(%{Route.key(%Route{entry: 72, variant: 2}) => route})
      mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 72, 1), entry: 72}}

      assert %WaypointRoute{} =
               Waypoints.resolve(routes, mob, %ScriptStep{command: :start_waypoints, datalong: 5, dataint3: 2})

      assert nil == Waypoints.resolve(routes, mob, %ScriptStep{command: :start_waypoints, datalong: 5})
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
