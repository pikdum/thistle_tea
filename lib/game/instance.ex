defmodule ThistleTea.Game.Instance do
  @moduledoc """
  Pure instance-copy membership and ownership transitions.
  """

  import Bitwise

  alias ThistleTea.Game.InstanceScript
  alias ThistleTea.Game.WorldRef

  @uint32_max 0xFFFFFFFF

  defmodule Copy do
    @moduledoc false
    defstruct [:world, :owner, :script_name, members: MapSet.new(), data: %{}, script_state: %{}]
  end

  defstruct copies: %{}, owner_index: %{}, member_index: %{}, bindings: %{}, next_id: 1

  def enter(instances, map_id, owner, guid, script_name \\ nil)

  def enter(%__MODULE__{} = instances, map_id, owner, guid, script_name) when is_integer(map_id) and is_integer(guid) do
    {instances, emptied} = remove_member(instances, guid)
    {world, instances} = find_bound_or_create(instances, map_id, owner, guid, script_name)
    copy = Map.fetch!(instances.copies, world)
    copy = %{copy | members: MapSet.put(copy.members, guid)}

    instances = %{
      instances
      | copies: Map.put(instances.copies, world, copy),
        member_index: Map.put(instances.member_index, guid, world),
        bindings: Map.put(instances.bindings, {map_id, guid}, world)
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

  def world_for_guid(%__MODULE__{} = instances, map_id, guid) when is_integer(map_id) and is_integer(guid) do
    Map.get(instances.bindings, {map_id, guid})
  end

  def member_world(%__MODULE__{} = instances, guid) when is_integer(guid) do
    Map.get(instances.member_index, guid)
  end

  def copy(%__MODULE__{copies: copies}, %WorldRef{} = world), do: Map.get(copies, world)

  def read(%__MODULE__{} = instances, %WorldRef{} = world, field) do
    with :ok <- validate_world(world),
         :ok <- validate_field(field),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, initial} <- initial_value(copy, field) do
      {:ok, Map.get(copy.data, field, initial)}
    end
  end

  def read(%__MODULE__{}, _world, _field), do: {:error, :open_world}

  def read_many(%__MODULE__{} = instances, %WorldRef{} = world, fields) do
    fields
    |> Enum.uniq()
    |> Map.new(&{&1, read(instances, world, &1)})
  end

  def command(%__MODULE__{} = instances, %WorldRef{} = world, field, value, mode) do
    with :ok <- validate_world(world),
         :ok <- validate_field(field),
         :ok <- validate_value(value),
         :ok <- validate_mode(mode),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, current} <- current_value(copy, field),
         updated = updated_value(current, value, mode),
         {:ok, stored, data, effects} <- InstanceScript.set_data(copy.script_name, copy.data, field, updated) do
      copy = %{copy | data: data}
      instances = %{instances | copies: Map.put(instances.copies, world, copy)}
      {:ok, stored, effects, instances}
    end
  end

  def command(%__MODULE__{}, _world, _field, _value, _mode), do: {:error, :open_world}

  def game_object_used(%__MODULE__{} = instances, %WorldRef{} = world, entry) when is_integer(entry) do
    with :ok <- validate_world(world),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, data, effects} <- InstanceScript.game_object_used(copy.script_name, copy.data, entry) do
      copy = %{copy | data: data}
      instances = %{instances | copies: Map.put(instances.copies, world, copy)}
      {:ok, effects, instances}
    end
  end

  def game_object_used(%__MODULE__{}, _world, _entry), do: {:error, :open_world}

  def game_object_spawned(%__MODULE__{} = instances, %WorldRef{} = world, entry) when is_integer(entry) do
    with :ok <- validate_world(world),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, effects} <- InstanceScript.game_object_spawned(copy.script_name, copy.data, copy.script_state, entry) do
      {:ok, effects, instances}
    end
  end

  def game_object_spawned(%__MODULE__{}, _world, _entry), do: {:error, :open_world}

  def creature_event(%__MODULE__{} = instances, %WorldRef{} = world, event) do
    with :ok <- validate_world(world),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, data, script_state, effects} <-
           InstanceScript.creature_event(copy.script_name, copy.data, copy.script_state, event) do
      copy = %{copy | data: data, script_state: script_state}
      instances = %{instances | copies: Map.put(instances.copies, world, copy)}
      {:ok, effects, instances}
    end
  end

  def creature_event(%__MODULE__{}, _world, _event), do: {:error, :open_world}

  def timer(%__MODULE__{} = instances, %WorldRef{} = world, key) do
    with :ok <- validate_world(world),
         {:ok, copy} <- fetch_copy(instances, world),
         {:ok, data, script_state, effects} <-
           InstanceScript.timer(copy.script_name, copy.data, copy.script_state, key) do
      copy = %{copy | data: data, script_state: script_state}
      instances = %{instances | copies: Map.put(instances.copies, world, copy)}
      {:ok, effects, instances}
    end
  end

  def timer(%__MODULE__{}, _world, _key), do: {:error, :open_world}

  def copies_for_owner(%__MODULE__{copies: copies}, owner) do
    copies
    |> Map.values()
    |> Enum.filter(&(&1.owner == owner))
    |> Enum.sort_by(& &1.world.instance_id)
  end

  def copies_for_guid(%__MODULE__{} = instances, guid) when is_integer(guid) do
    instances.bindings
    |> Enum.flat_map(fn
      {{_map_id, ^guid}, world} -> [world]
      {_binding, _world} -> []
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn world ->
      case Map.get(instances.copies, world) do
        %Copy{} = copy -> [copy]
        nil -> []
      end
    end)
    |> Enum.sort_by(&{&1.world.map_id, &1.world.instance_id})
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
            member_index: Map.put(instances.member_index, guid, world),
            bindings: Map.put(instances.bindings, {world.map_id, guid}, world)
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
            owner_index: Map.delete(instances.owner_index, {world.map_id, owner}),
            bindings: delete_world_bindings(instances.bindings, world)
        }

      _occupied_or_missing ->
        instances
    end
  end

  defp find_bound_or_create(%__MODULE__{} = instances, map_id, owner, guid, script_name) do
    case world_for_guid(instances, map_id, guid) do
      %WorldRef{} = world -> {world, instances}
      nil -> find_or_create(instances, {map_id, owner}, script_name)
    end
  end

  defp find_or_create(%__MODULE__{} = instances, owner_key, script_name) do
    case Map.get(instances.owner_index, owner_key) do
      %WorldRef{} = world ->
        {world, instances}

      nil ->
        {map_id, owner} = owner_key
        world = WorldRef.instance(map_id, instances.next_id)
        copy = %Copy{world: world, owner: owner, script_name: script_name}

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

  defp delete_world_bindings(bindings, world) do
    bindings
    |> Enum.reject(fn {_binding, bound_world} -> bound_world == world end)
    |> Map.new()
  end

  defp validate_world(%WorldRef{instance_id: instance_id}) when is_integer(instance_id), do: :ok
  defp validate_world(%WorldRef{}), do: {:error, :open_world}

  defp validate_field(field) when is_integer(field) and field >= 0 and field <= @uint32_max, do: :ok
  defp validate_field(field), do: {:error, {:invalid_field, field}}

  defp validate_value(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_value(value), do: {:error, {:invalid_value, value}}

  defp validate_mode(mode) when mode in [:raw, :increment, :decrement], do: :ok
  defp validate_mode(mode), do: {:error, {:invalid_mode, mode}}

  defp fetch_copy(%__MODULE__{copies: copies}, world) do
    case Map.get(copies, world) do
      %Copy{} = copy -> {:ok, copy}
      nil -> {:error, :missing_copy}
    end
  end

  defp initial_value(%Copy{script_name: nil}, _field), do: {:error, :no_instance_script}
  defp initial_value(%Copy{script_name: script_name}, field), do: InstanceScript.initial_value(script_name, field)

  defp current_value(copy, field) do
    with {:ok, initial} <- initial_value(copy, field) do
      {:ok, Map.get(copy.data, field, initial)}
    end
  end

  defp updated_value(_current, value, :raw), do: band(value, @uint32_max)
  defp updated_value(current, value, :increment), do: band(current + value, @uint32_max)
  defp updated_value(current, value, :decrement), do: max(current - band(value, @uint32_max), 0)
end
