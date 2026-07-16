defmodule ThistleTea.Game.Instance do
  @moduledoc """
  Pure instance-copy membership and ownership transitions.
  """

  alias ThistleTea.Game.WorldRef

  defmodule Copy do
    @moduledoc false
    defstruct [:world, :owner, members: MapSet.new()]
  end

  defstruct copies: %{}, owner_index: %{}, member_index: %{}, next_id: 1

  def enter(%__MODULE__{} = instances, map_id, owner, guid) when is_integer(map_id) and is_integer(guid) do
    {instances, emptied} = remove_member(instances, guid)
    owner_key = {map_id, owner}
    {world, instances} = find_or_create(instances, owner_key)
    copy = Map.fetch!(instances.copies, world)
    copy = %{copy | members: MapSet.put(copy.members, guid)}

    instances = %{
      instances
      | copies: Map.put(instances.copies, world, copy),
        member_index: Map.put(instances.member_index, guid, world)
    }

    emptied = if emptied != world, do: emptied
    {world, emptied, instances}
  end

  def leave(%__MODULE__{} = instances, guid, %WorldRef{} = world) when is_integer(guid) do
    case Map.get(instances.member_index, guid) do
      ^world -> remove_member(instances, guid)
      _other -> {instances, nil}
    end
  end

  def world_for(%__MODULE__{} = instances, map_id, owner) when is_integer(map_id) do
    Map.get(instances.owner_index, {map_id, owner})
  end

  def member_world(%__MODULE__{} = instances, guid) when is_integer(guid) do
    Map.get(instances.member_index, guid)
  end

  def copies_for_owner(%__MODULE__{copies: copies}, owner) do
    copies
    |> Map.values()
    |> Enum.filter(&(&1.owner == owner))
    |> Enum.sort_by(& &1.world.instance_id)
  end

  def join_copy(%__MODULE__{} = instances, guid, %WorldRef{} = world) when is_integer(guid) do
    case Map.get(instances.copies, world) do
      %Copy{} ->
        {instances, emptied} = remove_member(instances, guid)
        copy = Map.fetch!(instances.copies, world)
        copy = %{copy | members: MapSet.put(copy.members, guid)}

        instances = %{
          instances
          | copies: Map.put(instances.copies, world, copy),
            member_index: Map.put(instances.member_index, guid, world)
        }

        emptied = if emptied != world, do: emptied
        {:ok, emptied, instances}

      nil ->
        {:error, :not_found}
    end
  end

  def empty?(%__MODULE__{copies: copies}, %WorldRef{} = world) do
    case Map.get(copies, world) do
      %Copy{members: members} -> MapSet.size(members) == 0
      nil -> false
    end
  end

  def destroy_empty(%__MODULE__{} = instances, %WorldRef{} = world) do
    case Map.get(instances.copies, world) do
      %Copy{owner: owner, members: %MapSet{map: members}} when map_size(members) == 0 ->
        %{
          instances
          | copies: Map.delete(instances.copies, world),
            owner_index: Map.delete(instances.owner_index, {world.map_id, owner})
        }

      _occupied_or_missing ->
        instances
    end
  end

  defp find_or_create(%__MODULE__{} = instances, owner_key) do
    case Map.get(instances.owner_index, owner_key) do
      %WorldRef{} = world ->
        {world, instances}

      nil ->
        {map_id, owner} = owner_key
        world = WorldRef.instance(map_id, instances.next_id)
        copy = %Copy{world: world, owner: owner}

        instances = %{
          instances
          | copies: Map.put(instances.copies, world, copy),
            owner_index: Map.put(instances.owner_index, owner_key, world),
            next_id: instances.next_id + 1
        }

        {world, instances}
    end
  end

  defp remove_member(%__MODULE__{} = instances, guid) do
    case Map.pop(instances.member_index, guid) do
      {nil, _member_index} ->
        {instances, nil}

      {world, member_index} ->
        copy = Map.fetch!(instances.copies, world)
        copy = %{copy | members: MapSet.delete(copy.members, guid)}
        instances = %{instances | copies: Map.put(instances.copies, world, copy), member_index: member_index}
        emptied = if MapSet.size(copy.members) == 0, do: world
        {instances, emptied}
    end
  end
end
