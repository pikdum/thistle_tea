defmodule ThistleTea.Game.World.System.CreatureGroups do
  @moduledoc """
  Owns creature-group membership and creature links separately for each world
  copy. Entity owners report lifecycle transitions; group and link commands are
  delivered without calling back into those owners. Membership survives cell
  unloading and spawn reincarnation. A linked slave whose master forbids it to
  spawn is held dead until the master's death, respawn, or despawn lets it in.
  """
  use GenServer

  alias ThistleTea.Game.Core.Creature.CreatureGroup
  alias ThistleTea.Game.Core.Creature.CreatureGroup.Member
  alias ThistleTea.Game.Core.Creature.CreatureLink
  alias ThistleTea.Game.Core.Creature.Formation
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.CreatureGroup, as: CreatureGroupLoader
  alias ThistleTea.Game.World.Loader.CreatureLink, as: CreatureLinkLoader

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

  def spawn_allowed?(%Mob{} = entity, owner, server \\ __MODULE__) when is_pid(owner) do
    GenServer.call(server, {:spawn_allowed, entity.internal.world, entity.object.guid, owner})
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

  def members(world, guid, server \\ __MODULE__) do
    GenServer.call(server, {:members, world, guid})
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
       held: MapSet.new(),
       formation_table: create_formation_table(opts),
       catalog: Keyword.get(opts, :catalog, &CreatureGroupLoader.get/2),
       links: Keyword.get(opts, :links, &CreatureLinkLoader.links/2)
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

    held? = not respawn? and actor.alive? and not gate_open?(state, key)
    state = if held?, do: hold(state, key, actor), else: %{state | held: MapSet.delete(state.held, key)}
    actor = Map.fetch!(state.actors, key)

    state = ensure_group(state, world, id)
    state = %{state | tokens: Map.put(state.tokens, key, make_ref())}
    state = update_group_lifecycle(state, key, :respawn)
    state = publish_group(state, Map.get(state.memberships, key))

    state =
      if (respawn? or match?(%{alive?: false}, previous)) and actor.alive?,
        do: dispatch(state, key, :respawn),
        else: state

    {:reply, if(held?, do: :held, else: :ok), state}
  end

  defp handle_request({:spawn_allowed, world, guid, owner}, state) do
    case owned_actor(state, world, guid, owner) do
      {:ok, key, actor} ->
        if gate_open?(state, key),
          do: {:reply, true, %{state | held: MapSet.delete(state.held, key)}},
          else: {:reply, false, hold(state, key, actor)}

      _stale ->
        {:reply, true, state}
    end
  end

  defp handle_request({:join, world, guid, target, member, owner}, state) do
    with {:ok, key, _actor} <- owned_actor(state, world, guid, owner),
         nil <- Map.get(state.memberships, key),
         {^world, _target_id} = target_key <- Map.get(state.guids, target) do
      group_key = Map.get(state.memberships, target_key) || target_key
      {_world, leader} = group_key
      group = Map.get(state.groups, group_key) || runtime_group(state.actors[target_key], leader)
      {_world, id} = key
      group = CreatureGroup.add(group, id, member)
      state = put_group(state, world, group)
      state = catch_up_death(state, target_key, id)
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

  defp handle_request({:members, world, guid}, state) do
    members =
      with {^world, _id} = key <- Map.get(state.guids, guid),
           group_key when not is_nil(group_key) <- Map.get(state.memberships, key),
           %CreatureGroup{} = group <- Map.get(state.groups, group_key) do
        group
        |> CreatureGroup.member_ids()
        |> Enum.flat_map(&present_guids(Map.get(state.actors, {world, &1})))
      else
        _ungrouped -> []
      end

    {:reply, members, state}
  end

  defp handle_request({:valid_command, world, guid, token, owner}, state) do
    valid? =
      with {:ok, key, _actor} <- owned_actor(state, world, guid, owner),
           ^token <- Map.get(state.tokens, key) do
        not is_nil(Map.get(state.memberships, key)) or linked?(state, key)
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
         actors: reject_world(state.actors, world),
         held: MapSet.reject(state.held, &(elem(&1, 0) == world))
     }}
  end

  @impl GenServer
  def handle_cast({:event, world, guid, owner, {:waypoint, %WaypointRoute{} = route}}, state) do
    case owned_actor(state, world, guid, owner) do
      {:ok, {^world, _id} = key, actor} ->
        state = %{state | actors: Map.put(state.actors, key, %{actor | route: route})}
        {:noreply, reached_waypoint(state, key, route.destination_point)}

      _ungrouped ->
        {:noreply, state}
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
      {:noreply, dispatch(state, key, event)}
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
    state = %{state | held: MapSet.delete(state.held, key)}

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

  defp runtime_group(%{route: %WaypointRoute{destination_point: point}}, leader),
    do: CreatureGroup.reached_waypoint(CreatureGroup.new(leader), leader, point)

  defp runtime_group(_actor, leader), do: CreatureGroup.new(leader)

  defp catch_up_death(state, {world, source} = key, joined) do
    case Map.get(state.actors, key) do
      %{alive?: false} ->
        state = update_group_lifecycle(state, key, :death)
        group = state.groups[state.memberships[key]]

        group
        |> CreatureGroup.actions(source, :death, actors(state, world, group))
        |> Enum.filter(&(elem(&1, 0) == joined))
        |> Enum.each(&deliver(state, world, &1))

        state

      _alive ->
        state
    end
  end

  defp reached_waypoint(state, {world, id} = key, point) do
    group_key = Map.get(state.memberships, key)

    case Map.get(state.groups, group_key) do
      %CreatureGroup{} = group ->
        group = CreatureGroup.reached_waypoint(group, id, point)
        state = %{state | groups: Map.put(state.groups, group_key, group)}
        publish_group(state, {world, group.leader})

      nil ->
        state
    end
  end

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

  defp present_guids(%{guid: guid, present?: true}), do: [guid]
  defp present_guids(_absent), do: []

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
      |> Enum.each(&deliver(state, world, &1))
    end

    dispatch_links(state, key, event)
  end

  defp deliver(state, world, {target, action}) do
    member_key = {world, target}
    send(state.actors[member_key].pid, {:creature_group, state.tokens[member_key], command(action, state, world)})
  end

  defp dispatch_links(state, {world, id} = key, event) do
    {master_link, slave_links} = state.links.(world.map_id, id)
    source = Map.get(state.actors, key)

    slave_commands =
      for %CreatureLink{slave: slave} = link <- slave_links,
          %{present?: true} = actor <- [Map.get(state.actors, {world, slave})],
          command = slave_command(state, world, link, event, actor, source),
          not is_nil(command),
          do: {slave, command}

    commands = slave_commands ++ master_commands(state, world, master_link, event)
    Enum.each(commands, &deliver(state, world, &1))

    released = for {slave, :respawn} <- slave_commands, do: {world, slave}
    %{state | held: Enum.reduce(released, state.held, &MapSet.delete(&2, &1))}
  end

  defp slave_command(state, world, %CreatureLink{slave: slave} = link, event, actor, source) do
    CreatureLink.slave_command(link, event, actor) ||
      if(
        event in [:death, :despawn, :respawn] and MapSet.member?(state.held, {world, slave}) and
          CreatureLink.spawn_allowed?(link, source),
        do: :respawn
      )
  end

  defp master_commands(state, world, %CreatureLink{master: master} = link, event) do
    with %{present?: true} = actor <- Map.get(state.actors, {world, master}),
         command when not is_nil(command) <- CreatureLink.master_command(link, event, actor) do
      [{master, command}]
    else
      _none -> []
    end
  end

  defp master_commands(_state, _world, nil, _event), do: []

  defp gate_open?(state, {world, id}) do
    case state.links.(world.map_id, id) do
      {%CreatureLink{master: master} = link, _slaves} ->
        CreatureLink.spawn_allowed?(link, Map.get(state.actors, {world, master}))

      _unlinked ->
        true
    end
  end

  defp hold(state, key, actor) do
    %{
      state
      | held: MapSet.put(state.held, key),
        actors: Map.put(state.actors, key, %{actor | alive?: false, combat?: false})
    }
  end

  defp linked?(state, {world, id}) do
    case state.links.(world.map_id, id) do
      {nil, []} -> false
      _linked -> true
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
