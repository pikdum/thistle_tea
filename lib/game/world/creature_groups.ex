defmodule ThistleTea.Game.World.CreatureGroups do
  @moduledoc """
  Owns creature-group membership separately for each world copy. Entity owners
  report lifecycle transitions; group commands are delivered without calling back
  into those owners. Membership survives cell unloading and spawn reincarnation.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Formation
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.World.Loader.CreatureGroup, as: Catalog
  alias ThistleTea.Game.WorldRef

  require Logger

  @formation_table :creature_group_formations

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
      route: default_route(entity),
      spawn_position: spawn_position(entity),
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

  def formation(world, guid, server \\ __MODULE__)

  def formation(world, guid, __MODULE__) do
    if :ets.whereis(@formation_table) != :undefined, do: lookup_formation(@formation_table, world, guid)
  end

  def formation(world, guid, server), do: GenServer.call(server, {:formation, world, guid})

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
       formation_table: create_formation_table(opts),
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
    state = update_group_lifecycle(state, key, :respawn)
    state = publish_group(state, Map.get(state.memberships, key))
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
      state = publish_group(state, group_key)
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

  defp handle_request({:formation, world, guid}, state) do
    {:reply, lookup_formation(state.formation_table, world, guid), state}
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

    :ets.match_delete(state.formation_table, {{world, :_}, :_})

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
  def handle_cast({:event, world, guid, owner, {:waypoint, %WaypointRoute{} = route}}, state) do
    with {:ok, {^world, id} = key, actor} <- owned_actor(state, world, guid, owner),
         group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
         %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
      group = CreatureGroup.reached_waypoint(group, id, route.destination_point)
      actor = if is_struct(actor.route, WaypointRoute), do: %{actor | route: route}, else: actor
      state = %{state | groups: Map.put(state.groups, group_key, group), actors: Map.put(state.actors, key, actor)}
      {:noreply, publish_group(state, group_key)}
    else
      _ungrouped -> {:noreply, state}
    end
  rescue
    error ->
      Logger.error("creature group waypoint crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_cast({:event, world, guid, owner, event}, state) do
    with {:ok, key, actor} <- owned_actor(state, world, guid, owner),
         {:changed, updated} <- transition(actor, event) do
      state = %{state | actors: Map.put(state.actors, key, updated)}
      state = update_group_lifecycle(state, key, event)
      state = publish_group(state, Map.get(state.memberships, key))
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
      nil ->
        {:noreply, state}

      key ->
        state = state |> detach_actor(key) |> forget_ungrouped_actor(key)
        {:noreply, publish_group(state, Map.get(state.memberships, key))}
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

  defp default_route(%Mob{internal: %{spawn: %{movement_type: 2, waypoint_route: %WaypointRoute{} = route}}}), do: route
  defp default_route(%Mob{}), do: nil

  defp spawn_position(%Mob{internal: %{spawn: %{position: position}}}), do: position
  defp spawn_position(%Mob{}), do: nil

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
        Enum.each(CreatureGroup.member_ids(group), &clear_formation(state, {world, &1}))
        memberships = Enum.reduce(CreatureGroup.member_ids(group), state.memberships, &Map.put(&2, {world, &1}, nil))
        %{state | memberships: memberships, groups: Map.delete(state.groups, group_key)}
      else
        clear_formation(state, key)

        state = %{
          state
          | memberships: Map.put(state.memberships, key, nil),
            groups: Map.put(state.groups, group_key, CreatureGroup.remove(group, id))
        }

        publish_group(state, group_key)
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
        :ets.delete(state.formation_table, {elem(key, 0), guid})
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
  defp transition(actor, {:attack, target, _leash}), do: transition(actor, {:attack, target})
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

  defp update_group_lifecycle(state, {world, id} = key, event) do
    with group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
         %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
      updated =
        case event do
          :death -> CreatureGroup.on_death(group, id, actors(state, world, group))
          :respawn -> CreatureGroup.on_respawn(group, id)
          _event -> group
        end

      %{state | groups: Map.put(state.groups, group_key, updated)}
    else
      _ungrouped -> state
    end
  end

  defp create_formation_table(opts) do
    options = [:protected, read_concurrency: true]
    options = if Keyword.get(opts, :name, __MODULE__) == __MODULE__, do: [:named_table | options], else: options
    :ets.new(@formation_table, options)
  end

  defp lookup_formation(table, world, guid) do
    case :ets.lookup(table, {world, guid}) do
      [{_key, formation}] -> formation
      [] -> nil
    end
  end

  defp publish_group(state, nil), do: state

  defp publish_group(state, {world, _leader} = key) do
    case Map.get(state.groups, key) do
      %CreatureGroup{} = group ->
        if CreatureGroup.formation?(group) do
          Enum.each(CreatureGroup.member_ids(group), &publish_formation(state, world, group, &1))
        end

      nil ->
        :ok
    end

    state
  end

  defp publish_formation(state, world, group, id) do
    case Map.get(state.actors, {world, id}) do
      %{present?: true} = actor ->
        leader = Map.get(state.actors, {world, group.active_leader})
        original = Map.get(state.actors, {world, group.leader})
        role = if id == group.active_leader, do: :leader, else: :follower
        route = if role == :leader and id != group.leader and original, do: original.route

        formation = %Formation{
          token: state.tokens[{world, id}],
          role: role,
          leader_guid: present_guid(leader),
          member: Map.get(group.members, id),
          route: route,
          last_waypoint: group.last_waypoint,
          home_position: waypoint_position(original, group.last_waypoint),
          original_guid: present_guid(original),
          original_spawn: if(original, do: original.spawn_position)
        }

        key = {world, actor.guid}

        if lookup_formation(state.formation_table, world, actor.guid) != formation do
          :ets.insert(state.formation_table, {key, formation})
          send(actor.pid, :formation_changed)
        end

      _absent ->
        :ok
    end
  end

  defp present_guid(%{present?: true, guid: guid}), do: guid
  defp present_guid(_actor), do: nil

  defp waypoint_position(%{route: %WaypointRoute{points: points}}, point) when point > 0 do
    case Map.get(points, point) do
      %{position: {x, y, z, _orientation}} -> {x, y, z}
      nil -> nil
    end
  end

  defp waypoint_position(_actor, _point), do: nil

  defp clear_formation(state, {world, _id} = key) do
    case Map.get(state.actors, key) do
      %{present?: true} = actor ->
        :ets.delete(state.formation_table, {world, actor.guid})
        send(actor.pid, :formation_changed)

      _absent ->
        :ok
    end
  end

  defp reject_world(map, world), do: Map.reject(map, fn {{member_world, _id}, _value} -> member_world == world end)
end
