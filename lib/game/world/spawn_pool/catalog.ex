defmodule ThistleTea.Game.World.SpawnPool.Catalog do
  @moduledoc """
  Loads VMangos pool definitions once and exposes immutable spawn membership.
  """
  use GenServer

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.SpawnPool.Definition
  alias ThistleTea.Game.World.SpawnPool.Member

  @table :spawn_pool_catalog

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def group_for(kind, guid) when kind in [:creature, :game_object] and is_integer(guid) do
    case :ets.lookup(@table, {:member_group, kind, guid}) do
      [{{:member_group, ^kind, ^guid}, group}] -> group
      [] -> {:singleton, kind, guid}
    end
  end

  def data do
    :ets.lookup_element(@table, :data, 2)
  end

  def root_members(root_id) do
    catalog = data()
    collect_members(root_id, catalog.pools, MapSet.new())
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    catalog = load()
    :ets.insert(@table, {:data, catalog})

    Enum.each(catalog.member_pool, fn {{kind, guid}, pool_id} ->
      :ets.insert(@table, {{:member_group, kind, guid}, {:pool, root(pool_id, catalog.parent)}})
    end)

    {:ok, catalog}
  end

  defp load do
    case SQL.query!(
           Mangos.Repo,
           "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pool_template'",
           []
         ) do
      %{rows: [[1]]} -> load_data()
      _result -> %{pools: %{}, parent: %{}, member_pool: %{}}
    end
  end

  defp load_data do
    templates = Mangos.Repo.all(Mangos.PoolTemplate)
    pool_rows = Mangos.Repo.all(Mangos.PoolPool)
    parent = Map.new(pool_rows, &{&1.pool_id, &1.mother_pool})

    creature_members =
      Mangos.Repo.all(Mangos.PoolCreature)
      |> Enum.map(&{&1.pool_entry, member(:creature, &1.guid, &1.chance, &1.flags)})
      |> Kernel.++(creature_template_members())

    game_object_members =
      Mangos.Repo.all(Mangos.PoolGameObject)
      |> Enum.map(&{&1.pool_entry, member(:game_object, &1.guid, &1.chance, &1.flags)})
      |> Kernel.++(game_object_template_members())

    child_members =
      Enum.map(pool_rows, &{&1.mother_pool, member(:pool, &1.pool_id, &1.chance, &1.flags)})

    members_by_pool =
      Enum.group_by(child_members ++ game_object_members ++ creature_members, &elem(&1, 0), &elem(&1, 1))

    pools =
      Map.new(templates, fn template ->
        {template.entry,
         %Definition{
           id: template.entry,
           max_limit: max(template.max_limit || 1, 1),
           description: template.description,
           members: Map.get(members_by_pool, template.entry, [])
         }}
      end)

    member_pool =
      pools
      |> Map.values()
      |> Enum.flat_map(fn definition ->
        definition.members
        |> Enum.reject(&(&1.kind == :pool))
        |> Enum.map(&{Member.key(&1), definition.id})
      end)
      |> Map.new()

    %{pools: pools, parent: parent, member_pool: member_pool}
  end

  defp creature_template_members do
    template_rows = Mangos.Repo.all(Mangos.PoolCreatureTemplate)
    by_entry = Map.new(template_rows, &{&1.id, &1})

    from(c in Mangos.Creature, where: c.id in ^Map.keys(by_entry), select: {c.guid, c.id})
    |> Mangos.Repo.all()
    |> Enum.map(fn {guid, entry} ->
      row = Map.fetch!(by_entry, entry)
      {row.pool_entry, member(:creature, guid, row.chance, row.flags)}
    end)
  end

  defp game_object_template_members do
    template_rows = Mangos.Repo.all(Mangos.PoolGameObjectTemplate)
    by_entry = Map.new(template_rows, &{&1.id, &1})

    from(g in Mangos.GameObject, where: g.id in ^Map.keys(by_entry), select: {g.guid, g.id})
    |> Mangos.Repo.all()
    |> Enum.map(fn {guid, entry} ->
      row = Map.fetch!(by_entry, entry)
      {row.pool_entry, member(:game_object, guid, row.chance, row.flags)}
    end)
  end

  defp member(kind, id, chance, flags) do
    %Member{kind: kind, id: id, chance: abs(chance || 0.0), flags: flags || 0}
  end

  defp root(pool_id, parent, seen \\ MapSet.new()) do
    if MapSet.member?(seen, pool_id) do
      pool_id
    else
      case Map.get(parent, pool_id) do
        nil -> pool_id
        mother -> root(mother, parent, MapSet.put(seen, pool_id))
      end
    end
  end

  defp collect_members(pool_id, pools, seen) do
    if MapSet.member?(seen, pool_id) do
      []
    else
      collect_definition_members(Map.get(pools, pool_id), pools, MapSet.put(seen, pool_id))
    end
  end

  defp collect_definition_members(%Definition{} = definition, pools, seen) do
    Enum.flat_map(definition.members, fn
      %Member{kind: :pool, id: child_id} -> collect_members(child_id, pools, seen)
      %Member{} = member -> [member]
    end)
  end

  defp collect_definition_members(nil, _pools, _seen), do: []
end
