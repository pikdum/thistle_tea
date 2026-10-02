defmodule ThistleTea.Game.World.Loader.QuestEscort do
  @moduledoc """
  Boot loader for the C++-scripted escort quests in
  `Core.Quest.QuestEscort.Catalog`. It reads each escortee's
  `script_waypoint` path, or the escort's own `path`, lowers the escort into
  script steps with their broadcast texts resolved, registers the path in the
  waypoint catalog under `{:escort, quest_id}`, and appends the start steps
  to the quest's own start script. Runs after the waypoint and quest loaders.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Quest.QuestEscort
  alias ThistleTea.Game.Core.Quest.QuestEscort.Catalog
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Script
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  def load_all(escorts \\ Catalog.all()) do
    rows_by_entry = escorts |> Enum.filter(&is_nil(&1.path)) |> Enum.map(& &1.entry) |> load_rows()

    built =
      for %QuestEscort{} = escort <- escorts,
          rows = Map.get(rows_by_entry, escort.entry, []),
          escort.path != nil or rows != [] do
        {escort, build(escort, rows)}
      end

    built
    |> Map.new(fn {escort, {route, _start_steps}} -> {{:escort, escort.quest_id}, route} end)
    |> WaypointLoader.put_routes()

    Enum.each(built, fn {escort, {_route, start_steps}} ->
      QuestLoader.append_start_steps(escort.quest_id, start_steps)
    end)
  end

  def build(%QuestEscort{} = escort, rows, resolve_texts \\ &Script.resolve_texts/1) do
    rows = route_rows(escort, rows)
    last = Enum.max_by(rows, & &1.point)

    resolved =
      escort
      |> QuestEscort.point_steps(last.point, last.waittime)
      |> Map.put(:start, QuestEscort.start_steps(escort))
      |> resolve(resolve_texts)

    route = WaypointLoader.build_rows(rows, %{})

    points =
      Map.new(route.points, fn {point, waypoint} ->
        {point, %{waypoint | script_steps: Map.get(resolved, point, [])}}
      end)

    {%{route | points: points, pathfind?: true}, resolved.start}
  end

  defp route_rows(%QuestEscort{path: [_ | _] = path, entry: entry}, _rows) do
    path
    |> Enum.with_index()
    |> Enum.map(fn {{x, y, z, wait_ms}, point} ->
      %Mangos.ScriptWaypoint{entry: entry, point: point, position_x: x, position_y: y, position_z: z, waittime: wait_ms}
    end)
  end

  defp route_rows(%QuestEscort{}, [_ | _] = rows), do: rows

  defp resolve(steps_by_key, resolve_texts) do
    [%ScriptStep{sub_scripts: resolved}] = resolve_texts.([%ScriptStep{sub_scripts: steps_by_key}])
    resolved
  end

  defp load_rows([]), do: %{}

  defp load_rows(entries) do
    from(waypoint in Mangos.ScriptWaypoint, where: waypoint.entry in ^entries)
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
  end
end
