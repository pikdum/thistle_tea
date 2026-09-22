defmodule ThistleTea.Game.World.Loader.CreatureGroup do
  @moduledoc """
  Boot-loaded creature groups, indexed by map and spawn identity.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member

  @key {__MODULE__, :catalog}

  def load_all do
    query =
      from(g in Mangos.CreatureGroup,
        join: leader in Mangos.Creature,
        on: leader.guid == g.leader_guid,
        join: member in Mangos.Creature,
        on: member.guid == g.member_guid and member.map == leader.map,
        select: {leader.map, g}
      )

    catalog = query |> Mangos.Repo.all() |> build()
    :persistent_term.put(@key, catalog)
    :ok
  end

  def build(rows) do
    rows
    |> Enum.group_by(fn {map, row} -> {map, row.leader_guid} end)
    |> Enum.flat_map(fn {{map, leader}, rows} ->
      group =
        Enum.reduce(rows, CreatureGroup.new(leader), fn {_map, row}, group ->
          CreatureGroup.add(group, row.member_guid, %Member{distance: row.dist, angle: row.angle, flags: row.flags})
        end)

      Enum.map(CreatureGroup.member_ids(group), &{{map, &1}, group})
    end)
    |> Map.new()
  end

  def get(map, id), do: @key |> :persistent_term.get(%{}) |> Map.get({map, id})

  def formation_members(map, ids) do
    ids
    |> Enum.flat_map(&formation_ids(get(map, &1)))
    |> Enum.uniq()
  end

  defp formation_ids(%CreatureGroup{} = group) do
    if CreatureGroup.formation?(group), do: CreatureGroup.member_ids(group), else: []
  end

  defp formation_ids(nil), do: []
end
