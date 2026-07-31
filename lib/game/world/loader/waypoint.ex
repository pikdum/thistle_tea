defmodule ThistleTea.Game.World.Loader.Waypoint do
  @moduledoc """
  Boot-loaded VMangos waypoint catalog for guid, creature-template, and
  special scripted paths.
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
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
          Map.put(catalog, {origin, id}, WaypointRoute.build_rows(route_rows, scripts))
        end)
      end)

    :persistent_term.put(@catalog_key, catalog)
    :ok
  end

  def context do
    @catalog_key
    |> :persistent_term.get(%{})
    |> Waypoints.new()
  end
end
