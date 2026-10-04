defmodule ThistleTea.Game.World.Loader.CreatureLink do
  @moduledoc """
  Boot-loaded creature links, indexed by map and spawn identity.

  `creature_linking` ties one spawn to another directly. A
  `creature_linking_template` row ties every spawn of an entry on a map to
  a master entry: the nearest master spawn within the search range, or the
  map's only master spawn when the range is zero, as vmangos resolves it.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Creature.CreatureLink

  @key {__MODULE__, :catalog}

  def load_all do
    guid_rows =
      Mangos.Repo.all(
        from(l in Mangos.CreatureLinking,
          join: slave in Mangos.Creature,
          on: slave.guid == l.guid,
          join: master in Mangos.Creature,
          on: master.guid == l.master_guid and master.map == slave.map,
          select: {slave.map, l.guid, l.master_guid, l.flag}
        )
      )

    templates = Mangos.Repo.all(Mangos.CreatureLinkingTemplate)
    entries = Enum.flat_map(templates, &[&1.entry, &1.master_entry])

    spawns =
      Mangos.Repo.all(
        from(c in Mangos.Creature,
          where: c.id in ^entries,
          select: {c.guid, c.id, c.map, c.position_x, c.position_y}
        )
      )

    :persistent_term.put(@key, build(guid_rows, templates, spawns))
    :ok
  end

  def build(guid_rows, templates, spawns) do
    direct = Enum.map(guid_rows, fn {map, slave, master, flags} -> {map, link(slave, master, flags)} end)
    linked = MapSet.new(direct, fn {map, %CreatureLink{slave: slave}} -> {map, slave} end)

    templated =
      templates
      |> Enum.flat_map(&template_links(&1, spawns))
      |> Enum.reject(fn {map, %CreatureLink{slave: slave}} -> MapSet.member?(linked, {map, slave}) end)

    links = direct ++ templated
    by_slave = Map.new(links, fn {map, %CreatureLink{slave: slave} = link} -> {{map, slave}, link} end)

    by_master =
      Enum.group_by(links, fn {map, %CreatureLink{master: master}} -> {map, {:slaves, master}} end, &elem(&1, 1))

    Map.merge(by_slave, by_master)
  end

  def links(map, id) do
    catalog = :persistent_term.get(@key, %{})
    {Map.get(catalog, {map, id}), Map.get(catalog, {map, {:slaves, id}}, [])}
  end

  defp template_links(template, spawns) do
    masters =
      for {guid, entry, map, x, y} <- spawns, entry == template.master_entry, map == template.map, do: {guid, x, y}

    for {guid, entry, map, x, y} <- spawns,
        entry == template.entry,
        map == template.map,
        master = template_master(masters, {x, y}, template.search_range),
        not is_nil(master),
        do: {map, link(guid, master, template.flag)}
  end

  defp template_master([{master, _x, _y}], _position, 0), do: master
  defp template_master(_masters, _position, 0), do: nil

  defp template_master(masters, {x, y}, range) do
    masters
    |> Enum.map(fn {master, mx, my} -> {master, (x - mx) * (x - mx) + (y - my) * (y - my)} end)
    |> Enum.filter(fn {_master, distance_sq} -> distance_sq < range * range end)
    |> Enum.min_by(&elem(&1, 1), fn -> {nil, nil} end)
    |> elem(0)
  end

  defp link(slave, master, flags), do: %CreatureLink{slave: slave, master: master, flags: flags}
end
