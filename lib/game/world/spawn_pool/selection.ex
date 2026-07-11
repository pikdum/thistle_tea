defmodule ThistleTea.Game.World.SpawnPool.Selection do
  @moduledoc """
  Pure VMangos-compatible pool selection and member replacement.
  """

  alias ThistleTea.Game.World.SpawnPool.Definition
  alias ThistleTea.Game.World.SpawnPool.Member

  defstruct direct: %{}, leaves: MapSet.new()

  def initialize(root_id, catalog, available, picker \\ &default_picker/1) do
    select_pool(%__MODULE__{}, root_id, catalog, available, picker)
  end

  def replace(%__MODULE__{} = selection, root_id, trigger_key, catalog, available, picker \\ &default_picker/1) do
    case Map.fetch(catalog.member_pool, trigger_key) do
      {:ok, leaf_pool} ->
        case Map.get(catalog.parent, leaf_pool) do
          nil ->
            replace_direct(selection, root_id, member_for(trigger_key), catalog, available, picker)

          parent_id ->
            replace_direct(selection, parent_id, %Member{kind: :pool, id: leaf_pool}, catalog, available, picker)
        end

      :error ->
        initialize(root_id, catalog, available, picker)
    end
  end

  defp replace_direct(selection, pool_id, trigger, catalog, available, picker) do
    selected = Map.get(selection.direct, pool_id, [])

    if Enum.any?(selected, &(Member.key(&1) == Member.key(trigger))) do
      selection = remove_member(selection, trigger)
      excluded = Map.get(selection.direct, pool_id, []) |> MapSet.new(&Member.key/1)

      case choose(pool_id, catalog, available, excluded, picker) do
        nil -> selection
        member -> add_member(selection, pool_id, member, catalog, available, picker)
      end
    else
      selection
    end
  end

  defp select_pool(selection, pool_id, catalog, available, picker) do
    case Map.get(catalog.pools, pool_id) do
      %Definition{max_limit: limit} -> fill(selection, pool_id, limit, catalog, available, picker)
      nil -> selection
    end
  end

  defp fill(selection, pool_id, limit, catalog, available, picker) do
    selected = Map.get(selection.direct, pool_id, [])

    if length(selected) >= limit do
      selection
    else
      excluded = selected |> MapSet.new(&Member.key/1)

      case choose(pool_id, catalog, available, excluded, picker) do
        nil ->
          selection

        member ->
          selection
          |> add_member(pool_id, member, catalog, available, picker)
          |> fill(pool_id, limit, catalog, available, picker)
      end
    end
  end

  defp choose(pool_id, catalog, available, excluded, picker) do
    definition = Map.fetch!(catalog.pools, pool_id)

    definition.members
    |> Enum.reject(&(MapSet.member?(excluded, Member.key(&1)) or not available?(&1, catalog, available)))
    |> first_member_group()
    |> choose_member(definition.max_limit, picker)
  end

  defp first_member_group(members) do
    Enum.find_value([:pool, :game_object, :creature], [], fn kind ->
      case Enum.filter(members, &(&1.kind == kind)) do
        [] -> nil
        grouped -> grouped
      end
    end)
  end

  defp choose_member([], _limit, _picker), do: nil

  defp choose_member(members, limit, picker) when limit > 1 do
    picker.(members)
  end

  defp choose_member(members, 1, picker) do
    explicit = Enum.filter(members, &((&1.chance || 0) > 0))
    equal = Enum.reject(members, &((&1.chance || 0) > 0))

    case weighted(explicit) do
      nil -> if equal != [], do: picker.(equal)
      member -> member
    end
  end

  defp weighted([]), do: nil

  defp weighted(members) do
    roll = :rand.uniform() * 100

    Enum.reduce_while(members, roll, fn member, remaining ->
      remaining = remaining - member.chance
      if remaining < 0, do: {:halt, member}, else: {:cont, remaining}
    end)
    |> case do
      %Member{} = member -> member
      _remaining -> nil
    end
  end

  defp available?(%Member{kind: kind, id: id}, _catalog, available) when kind in [:creature, :game_object] do
    MapSet.member?(available, {kind, id})
  end

  defp available?(%Member{kind: :pool, id: pool_id}, catalog, available) do
    pool_has_available_member?(pool_id, catalog, available, MapSet.new())
  end

  defp pool_has_available_member?(pool_id, catalog, available, seen) do
    if MapSet.member?(seen, pool_id) do
      false
    else
      pool_members_available?(Map.get(catalog.pools, pool_id), catalog, available, MapSet.put(seen, pool_id))
    end
  end

  defp pool_members_available?(%Definition{members: members}, catalog, available, seen) do
    Enum.any?(members, fn
      %Member{kind: :pool, id: child_id} -> pool_has_available_member?(child_id, catalog, available, seen)
      %Member{} = member -> available?(member, catalog, available)
    end)
  end

  defp pool_members_available?(nil, _catalog, _available, _seen), do: false

  defp add_member(selection, pool_id, %Member{kind: :pool, id: child_id} = member, catalog, available, picker) do
    selection
    |> put_direct(pool_id, member)
    |> select_pool(child_id, catalog, available, picker)
  end

  defp add_member(selection, pool_id, %Member{} = member, _catalog, _available, _picker) do
    selection
    |> put_direct(pool_id, member)
    |> Map.update!(:leaves, &MapSet.put(&1, Member.key(member)))
  end

  defp put_direct(selection, pool_id, member) do
    direct = Map.update(selection.direct, pool_id, [member], &[member | &1])
    %{selection | direct: direct}
  end

  defp remove_member(selection, %Member{kind: :pool, id: child_id} = member) do
    selection
    |> remove_from_direct(member)
    |> remove_pool_tree(child_id)
  end

  defp remove_member(selection, %Member{} = member) do
    selection
    |> remove_from_direct(member)
    |> Map.update!(:leaves, &MapSet.delete(&1, Member.key(member)))
  end

  defp remove_from_direct(selection, member) do
    direct =
      Map.new(selection.direct, fn {pool_id, members} ->
        {pool_id, Enum.reject(members, &(Member.key(&1) == Member.key(member)))}
      end)

    %{selection | direct: direct}
  end

  defp remove_pool_tree(selection, pool_id) do
    members = Map.get(selection.direct, pool_id, [])

    selection =
      Enum.reduce(members, selection, fn
        %Member{kind: :pool, id: child_id}, acc -> remove_pool_tree(acc, child_id)
        %Member{} = member, acc -> Map.update!(acc, :leaves, &MapSet.delete(&1, Member.key(member)))
      end)

    %{selection | direct: Map.delete(selection.direct, pool_id)}
  end

  defp member_for({kind, id}), do: %Member{kind: kind, id: id}
  defp default_picker(members), do: Enum.random(members)
end
