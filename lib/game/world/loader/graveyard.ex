defmodule ThistleTea.Game.World.Loader.Graveyard do
  @moduledoc "Cached graveyard links with area, faction, and dungeon-entrance selection."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Pathfinding

  @team_alliance 469
  @team_horde 67
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]
  @supported_patch 10
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    links =
      Mangos.Repo.all(
        from(g in Mangos.GameGraveyardZone, where: g.patch_min <= @supported_patch and g.patch_max >= @supported_patch)
      )

    ids = links |> Enum.map(& &1.id) |> Enum.uniq()
    locations = DBC.all(from(l in WorldSafeLocs, where: l.id in ^ids))
    load(links, locations)
  end

  def load(links, locations, table \\ __MODULE__) do
    locations = Map.new(locations, &{&1.id, &1})

    links
    |> Enum.group_by(& &1.ghost_zone)
    |> Enum.each(fn {area, links} ->
      graveyards = Enum.flat_map(links, &graveyard(&1, locations)) |> Enum.sort_by(& &1.id)
      :ets.insert(table, {area, graveyards})
    end)
  end

  def for_area(area, table \\ __MODULE__) do
    case :ets.lookup(table, area) do
      [{^area, graveyards}] -> graveyards
      _missing -> []
    end
  end

  def team_for_race(race) when race in @alliance_races, do: @team_alliance
  def team_for_race(race) when race in @horde_races, do: @team_horde
  def team_for_race(_race), do: nil

  def closest(map, position, team, candidates \\ &for_area/1) do
    dungeon = Map.get(MapTemplate.dungeons(), map)

    with {zone, area} <- Pathfinding.get_zone_and_area(map, position) || dungeon_zone(dungeon) do
      entrance =
        case dungeon do
          %Dungeon{ghost_entrance: entrance} -> entrance
          _missing -> nil
        end

      closest_of(candidates.(area), map, position, team, entrance) ||
        closest_of(candidates.(zone), map, position, team, entrance)
    end
  end

  defp dungeon_zone(%Dungeon{zone_id: zone}) when is_integer(zone) and zone > 0, do: {zone, zone}
  defp dungeon_zone(_dungeon), do: nil

  def closest_of(graveyards, map, position, team, entrance \\ nil) do
    graveyards
    |> Enum.filter(fn %{faction: faction} -> faction == 0 or is_nil(team) or faction == team end)
    |> Enum.min_by(&rank(&1, map, position, entrance), fn -> nil end)
  end

  defp rank(%{map: map, position: target, id: id}, map, position, _entrance) do
    {0, Math.distance(position, target), id}
  end

  defp rank(%{map: map, position: {x, y, _z}, id: id}, _map, _position, {map, ex, ey}) when ex != 0.0 or ey != 0.0 do
    {1, (x - ex) * (x - ex) + (y - ey) * (y - ey), id}
  end

  defp rank(%{id: id}, _map, _position, _entrance), do: {2, 0, id}

  defp graveyard(link, locations) do
    case Map.get(locations, link.id) do
      nil ->
        []

      loc ->
        [%{id: loc.id, map: loc.map, position: {loc.location_x, loc.location_y, loc.location_z}, faction: link.faction}]
    end
  end
end
