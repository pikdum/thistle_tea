defmodule ThistleTea.Game.World.CreatureGroups do
  @moduledoc """
  Owns creature-group membership separately for each world copy. Entity owners
  report lifecycle transitions; group commands are delivered without calling back
  into those owners. Membership survives cell unloading and spawn reincarnation.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.World.Loader.CreatureGroup, as: Catalog
  alias ThistleTea.Game.WorldRef

  require Logger

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def register(%Mob{} = entity, owner, server \\ __MODULE__) when is_pid(owner) do
    register_entity(entity, owner, server, false)
  end

  def respawn(%Mob{} = entity, owner, server \\ __MODULE__) when is_pid(owner) do
    register_entity(entity, owner, server, true)
  end

  defp register_entity(entity, owner, server, respawn?) do
    key = {entity.internal.world, identity(entity)}

    actor = %{
      guid: entity.object.guid,
      entry: entity.object.entry,
      pid: owner,
      alive?: entity.unit.health > 0,
      combat?: entity.internal.in_combat == true
    }

    GenServer.call(server, {:register, key, actor, respawn?})
  end

  def event(%Mob{} = entity, event, owner, server \\ __MODULE__) when is_pid(owner) do
    GenServer.cast(server, {:event, entity.internal.world, entity.object.guid, owner, event})
  end

  def join(world, guid, target, %Member{} = member, owner, server \\ __MODULE__) do
    GenServer.call(server, {:join, world, guid, target, member, owner})
  end

  def leave(world, guid, owner, server \\ __MODULE__) do
    GenServer.call(server, {:leave, world, guid, owner})
  end

  def snapshot(world, guid, server \\ __MODULE__) do
    GenServer.call(server, {:snapshot, world, guid})
  end

  def valid_command?(world, guid, token, owner, server \\ __MODULE__) do
    GenServer.call(server, {:valid_command, world, guid, token, owner})
  end

  def stop_world(%WorldRef{} = world, server \\ __MODULE__) do
    GenServer.call(server, {:stop_world, world})
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       groups: %{},
       memberships: %{},
       tokens: %{},
       actors: %{},
       guids: %{},
       monitors: %{},
       catalog: Keyword.get(opts, :catalog, &Catalog.get/2)
     }}
  end

  @impl GenServer
  def handle_call(request, _from, state) do
    handle_request(request, state)
  rescue
    error ->
      Logger.error("creature group request crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :group_request_failed}, state}
  end

  defp handle_request({:register, {world, id} = key, actor, respawn?}, state) do
    previous = Map.get(state.actors, key)
    state = detach_actor(state, key)
    ref = Process.monitor(actor.pid)
    actor = Map.merge(actor, %{ref: ref, present?: true})

    state = %{
      state
      | actors: Map.put(state.actors, key, actor),
        guids: Map.put(state.guids, actor.guid, key),
        monitors: Map.put(state.monitors, ref, key)
    }

    state = ensure_group(state, world, id)
    state = %{state | tokens: Map.put(state.tokens, key, make_ref())}
    if (respawn? or match?(%{alive?: false}, previous)) and actor.alive?, do: dispatch(state, key, :respawn)
    {:reply, :ok, state}
  end

  defp handle_request({:join, world, guid, target, member, owner}, state) do
    with {:ok, key, _actor} <- owned_actor(state, world, guid, owner),
         nil <- Map.get(state.memberships, key),
         {^world, _target_id} = target_key <- Map.get(state.guids, target) do
      group_key = Map.get(state.memberships, target_key) || target_key
      {_world, leader} = group_key
      group = Map.get(state.groups, group_key, CreatureGroup.new(leader))
      {_world, id} = key
      group = CreatureGroup.add(group, id, member)
      state = put_group(state, world, group)
      {:reply, :ok, state}
    else
      _invalid -> {:reply, {:error, :invalid_membership}, state}
    end
  end

  defp handle_request({:leave, world, guid, owner}, state) do
    case owned_actor(state, world, guid, owner) do
      {:ok, key, _actor} -> {:reply, :ok, leave_group(state, key)}
      _invalid -> {:reply, {:error, :not_owner}, state}
    end
  end

  defp handle_request({:snapshot, world, guid}, state) do
    result =
      with {^world, id} = key <- Map.get(state.guids, guid),
           group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
           %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
        %{leader: group.leader, dead?: CreatureGroup.dead?(group, id, actors(state, world, group))}
      else
        _ungrouped ->
          case Map.get(state.guids, guid) do
            {^world, _id} -> %{leader: nil, dead?: true}
            _missing -> nil
          end
      end

    {:reply, result, state}
  end

  defp handle_request({:valid_command, world, guid, token, owner}, state) do
    valid? =
      with {:ok, key, _actor} <- owned_actor(state, world, guid, owner),
           ^token <- Map.get(state.tokens, key) do
        not is_nil(Map.get(state.memberships, key))
      else
        _stale -> false
      end

    {:reply, valid?, state}
  end

  defp handle_request({:stop_world, world}, state) do
    state =
      state.actors
      |> Map.keys()
      |> Enum.filter(&(elem(&1, 0) == world))
      |> Enum.reduce(state, &detach_actor(&2, &1))

    {:reply, :ok,
     %{
       state
       | groups: reject_world(state.groups, world),
         memberships: reject_world(state.memberships, world),
         tokens: reject_world(state.tokens, world),
         actors: reject_world(state.actors, world)
     }}
  end

  @impl GenServer
  def handle_cast({:event, world, guid, owner, event}, state) do
    with {:ok, key, actor} <- owned_actor(state, world, guid, owner),
         {:changed, updated} <- transition(actor, event) do
      state = %{state | actors: Map.put(state.actors, key, updated)}
      dispatch(state, key, event)
      {:noreply, state}
    else
      _unchanged -> {:noreply, state}
    end
  rescue
    error ->
      Logger.error("creature group event crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil -> {:noreply, state}
      key -> {:noreply, state |> detach_actor(key) |> forget_ungrouped_actor(key)}
    end
  rescue
    error ->
      Logger.error("creature group cleanup crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  defp forget_ungrouped_actor(state, key) do
    if is_nil(Map.get(state.memberships, key)) do
      %{state | actors: Map.delete(state.actors, key), tokens: Map.delete(state.tokens, key)}
    else
      state
    end
  end

  defp identity(%Mob{object: %{guid: guid}, internal: %{spawn: %{temporary?: true}}}), do: {:runtime, guid}
  defp identity(%Mob{internal: %{creature: %{db_guid: id}}}) when is_integer(id) and id > 0, do: id
  defp identity(%Mob{object: %{guid: guid}}), do: {:runtime, guid}

  defp ensure_group(state, world, id) do
    if Map.has_key?(state.memberships, {world, id}) do
      state
    else
      case state.catalog.(world.map_id, id) do
        %CreatureGroup{} = group -> put_group(state, world, group)
        nil -> state
      end
    end
  end

  defp put_group(state, world, group) do
    key = {world, group.leader}
    memberships = Enum.reduce(CreatureGroup.member_ids(group), state.memberships, &Map.put(&2, {world, &1}, key))

    tokens =
      Enum.reduce(CreatureGroup.member_ids(group), state.tokens, fn id, tokens ->
        member_key = {world, id}
        if Map.get(state.memberships, member_key) == key, do: tokens, else: Map.put(tokens, member_key, make_ref())
      end)

    %{state | memberships: memberships, tokens: tokens, groups: Map.put(state.groups, key, group)}
  end

  defp leave_group(state, {world, id} = key) do
    with group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
         %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
      if id == group.leader do
        memberships = Enum.reduce(CreatureGroup.member_ids(group), state.memberships, &Map.put(&2, {world, &1}, nil))
        %{state | memberships: memberships, groups: Map.delete(state.groups, group_key)}
      else
        %{
          state
          | memberships: Map.put(state.memberships, key, nil),
            groups: Map.put(state.groups, group_key, CreatureGroup.remove(group, id))
        }
      end
    else
      _ungrouped -> state
    end
  end

  defp owned_actor(state, world, guid, owner) do
    with {^world, _id} = key <- Map.get(state.guids, guid),
         %{pid: ^owner, present?: true} = actor <- Map.get(state.actors, key) do
      {:ok, key, actor}
    else
      _stale -> :error
    end
  end

  defp detach_actor(state, key) do
    case Map.get(state.actors, key) do
      %{ref: ref, guid: guid} = actor when is_reference(ref) ->
        Process.demonitor(ref, [:flush])
        actor = %{actor | ref: nil, pid: nil, present?: false}

        %{
          state
          | actors: Map.put(state.actors, key, actor),
            guids: Map.delete(state.guids, guid),
            monitors: Map.delete(state.monitors, ref)
        }

      _missing ->
        state
    end
  end

  defp transition(%{combat?: false, alive?: true} = actor, {:attack, _target}), do: {:changed, %{actor | combat?: true}}
  defp transition(%{combat?: true} = actor, :evade), do: {:changed, %{actor | combat?: false}}
  defp transition(%{alive?: true} = actor, :death), do: {:changed, %{actor | alive?: false, combat?: false}}
  defp transition(%{alive?: true} = actor, :despawn), do: {:changed, %{actor | alive?: false, combat?: false}}
  defp transition(%{alive?: false} = actor, :respawn), do: {:changed, %{actor | alive?: true, combat?: false}}
  defp transition(%{combat?: true} = actor, :combat_stop), do: {:changed, %{actor | combat?: false}}
  defp transition(_actor, _event), do: :unchanged

  defp dispatch(state, {world, id} = key, event) do
    with group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
         %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
      group
      |> CreatureGroup.actions(id, event, actors(state, world, group))
      |> Enum.each(fn {target, action} ->
        member_key = {world, target}
        send(state.actors[member_key].pid, {:creature_group, state.tokens[member_key], command(action, state, world)})
      end)
    end
  end

  defp command({:member_died, source, leader?}, state, world) do
    actor = state.actors[{world, source}]
    {:member_died, actor.guid, actor.entry, leader?}
  end

  defp command(action, _state, _world), do: action

  defp actors(state, world, group) do
    Map.new(CreatureGroup.member_ids(group), &{&1, Map.get(state.actors, {world, &1})})
  end

  defp reject_world(map, world), do: Map.reject(map, fn {{member_world, _id}, _value} -> member_world == world end)
end
