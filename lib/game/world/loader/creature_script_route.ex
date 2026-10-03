defmodule ThistleTea.Game.World.Loader.CreatureScriptRoute do
  @moduledoc """
  Boot loader for the paths `Core.AI.CreatureScript` ports walk. Each route
  is its creature's `script_waypoint` path with the port's point steps
  attached, their broadcast texts resolved, registered in the waypoint
  catalog under `{:script, entry}` for `start_waypoints` source 5. Runs
  after the waypoint loader.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.World.Loader.Script
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  def load_all(routes \\ CreatureScript.routes()) do
    rows_by_entry = routes |> Map.keys() |> load_rows()

    routes
    |> Enum.flat_map(fn {entry, point_steps} ->
      case Map.get(rows_by_entry, entry, []) do
        [] -> []
        rows -> [{{:script, entry}, build(rows, point_steps)}]
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

  defp load_rows([]), do: %{}

  defp load_rows(entries) do
    from(waypoint in Mangos.ScriptWaypoint, where: waypoint.entry in ^entries)
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
  end
end
