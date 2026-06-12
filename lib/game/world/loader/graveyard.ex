defmodule ThistleTea.Game.World.Loader.Graveyard do
  @moduledoc false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World.Pathfinding

  @team_alliance 469
  @team_horde 67
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def team_for_race(race) when race in @alliance_races, do: @team_alliance
  def team_for_race(race) when race in @horde_races, do: @team_horde
  def team_for_race(_race), do: nil

  def closest(map, {x, y, z} = position, team) do
    with {zone, _area} <- Pathfinding.get_zone_and_area(map, position) do
      zone
      |> graveyards_for_zone()
      |> closest_of(map, {x, y, z}, team)
    end
  end

  def closest_of(graveyards, map, position, team) do
    candidates =
      Enum.filter(graveyards, fn %{faction: faction} ->
        faction == 0 or is_nil(team) or faction == team
      end)

    candidates
    |> Enum.filter(fn %{map: graveyard_map} -> graveyard_map == map end)
    |> Enum.min_by(fn %{position: graveyard_position} -> Math.distance(position, graveyard_position) end, fn -> nil end)
    |> case do
      nil -> List.first(candidates)
      graveyard -> graveyard
    end
  end

  defp graveyards_for_zone(zone) do
    case :ets.lookup(__MODULE__, zone) do
      [{^zone, graveyards}] -> graveyards
      _ -> cache(zone, load_graveyards_for_zone(zone))
    end
  end

  defp cache(zone, graveyards) do
    :ets.insert(__MODULE__, {zone, graveyards})
    graveyards
  end

  defp load_graveyards_for_zone(zone) do
    links =
      Mangos.Repo.all(from(g in Mangos.GameGraveyardZone, where: g.ghost_zone == ^zone))

    factions = Map.new(links, fn %Mangos.GameGraveyardZone{id: id, faction: faction} -> {id, faction} end)

    case Map.keys(factions) do
      [] ->
        []

      ids ->
        DBC.all(from(l in WorldSafeLocs, where: l.id in ^ids))
        |> Enum.map(fn %WorldSafeLocs{} = loc ->
          %{
            id: loc.id,
            map: loc.map,
            position: {loc.location_x, loc.location_y, loc.location_z},
            faction: Map.get(factions, loc.id, 0)
          }
        end)
    end
  end
end
