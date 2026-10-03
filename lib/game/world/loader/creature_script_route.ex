defmodule ThistleTea.Game.World.Loader.CreatureScriptRoute do
  @moduledoc """
  Boot loader for the paths `Core.AI.CreatureScript` ports walk. Each route
  is its creature's `script_waypoint` path, or the path the port gives
  itself, with the port's point steps attached, their broadcast texts
  resolved, registered in the waypoint catalog under
  `{:script, entry, variant}` for `start_waypoints` source 5. Runs after the
  waypoint loader.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.World.Loader.Script
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  def load_all(routes \\ CreatureScript.routes()) do
    rows_by_entry = routes |> Enum.filter(&is_nil(&1.path)) |> Enum.map(& &1.entry) |> Enum.uniq() |> load_rows()

    routes
    |> Enum.flat_map(fn %Route{} = route ->
      case route_rows(route, Map.get(rows_by_entry, route.entry, [])) do
        [] -> []
        rows -> [{Route.key(route), build(rows, route.points)}]
      end
    end)
    |> Map.new()
    |> WaypointLoader.put_routes()
  end

  def build([_ | _] = rows, point_steps, resolve_texts \\ &Script.resolve_texts/1) when is_map(point_steps) do
    [%ScriptStep{sub_scripts: resolved}] = resolve_texts.([%ScriptStep{sub_scripts: point_steps}])
    route = WaypointLoader.build_rows(rows, %{})

    points =
      Map.new(route.points, fn {point, waypoint} ->
        {point, %{waypoint | script_steps: Map.get(resolved, point, [])}}
      end)

    %{route | points: points, pathfind?: true}
  end

  def route_rows(%Route{path: [_ | _] = path, entry: entry}, _rows) do
    path
    |> Enum.with_index()
    |> Enum.map(fn {{x, y, z, wait_ms}, point} ->
      %Mangos.ScriptWaypoint{entry: entry, point: point, position_x: x, position_y: y, position_z: z, waittime: wait_ms}
    end)
  end

  def route_rows(%Route{path: nil}, rows), do: rows

  defp load_rows([]), do: %{}

  defp load_rows(entries) do
    from(waypoint in Mangos.ScriptWaypoint, where: waypoint.entry in ^entries)
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
  end
end
