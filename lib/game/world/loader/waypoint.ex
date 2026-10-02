defmodule ThistleTea.Game.World.Loader.Waypoint do
  @moduledoc """
  Boot-loaded VMangos waypoint catalog for guid, creature-template, and
  special scripted paths.
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.World.Loader.Script

  @catalog_key {__MODULE__, :catalog}

  def init do
    :persistent_term.put(@catalog_key, %{})
    :ok
  end

  def load_all do
    sources = [
      {:guid, Mangos.CreatureMovement, :id},
      {:entry, Mangos.CreatureMovementTemplate, :entry},
      {:special, Mangos.CreatureMovementSpecial, :id}
    ]

    rows_by_source =
      Map.new(sources, fn {origin, schema, key} ->
        {origin, {Mangos.Repo.all(schema), key}}
      end)

    scripts =
      rows_by_source
      |> Map.values()
      |> Enum.flat_map(fn {rows, _key} -> Enum.map(rows, & &1.script_id) end)
      |> Enum.filter(&(&1 > 0))
      |> then(&Script.load_by_ids(Mangos.CreatureMovementScript, &1))

    catalog =
      Enum.reduce(rows_by_source, %{}, fn {origin, {rows, key}}, catalog ->
        rows
        |> Enum.group_by(&Map.fetch!(&1, key))
        |> Enum.reduce(catalog, fn {id, route_rows}, catalog ->
          route = build_rows(route_rows, scripts)
          Map.put(catalog, {origin, id}, %{route | pathfind?: origin != :special})
        end)
      end)

    :persistent_term.put(@catalog_key, catalog)
    :ok
  end

  def put_routes(routes) when is_map(routes) do
    catalog = @catalog_key |> :persistent_term.get(%{}) |> Map.merge(routes)
    :persistent_term.put(@catalog_key, catalog)
    :ok
  end

  def context do
    @catalog_key
    |> :persistent_term.get(%{})
    |> Waypoints.new()
  end

  def build(%Mangos.Creature{creature_movement: []}), do: nil

  def build(%Mangos.Creature{creature_movement: nil}), do: nil

  def build(
        %Mangos.Creature{position_x: x, position_y: y, position_z: z, creature_movement: creature_movement} = creature
      ) do
    route = build_rows(creature_movement, creature.movement_scripts)
    closest_point = closest_point(creature_movement, {x, y, z})
    %{route | destination_point: closest_point, cyclic?: creature.movement_type == 3}
  end

  def build_rows(rows, scripts_by_id) when is_list(rows) and rows != [] and is_map(scripts_by_id) do
    points =
      Map.new(rows, fn row ->
        {row.point,
         %Waypoint{
           position: {row.position_x, row.position_y, row.position_z, orientation(row.orientation)},
           wait_time: row.waittime,
           script_steps: Map.get(scripts_by_id, row.script_id, [])
         }}
      end)

    first_point = rows |> Enum.map(& &1.point) |> Enum.min()

    %WaypointRoute{
      first_point: first_point,
      destination_point: first_point,
      points: points
    }
  end

  defp orientation(100.0), do: nil

  defp orientation(orientation), do: orientation

  defp closest_point(creature_movement, {x, y, z}) do
    creature_movement
    |> Enum.min_by(fn %Mangos.CreatureMovement{} = cm ->
      Math.distance({cm.position_x, cm.position_y, cm.position_z}, {x, y, z})
    end)
    |> Map.get(:point)
  end
end
