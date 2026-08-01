defmodule ThistleTea.Game.World do
  @moduledoc """
  World-level spatial queries and position upkeep: nearby players/mobs/units
  by range, and updating an entity's place in the spatial hash tables.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Corpse, as: CorpseServer
  alias ThistleTea.Game.Entity.Server.DynamicObject, as: DynamicObjectServer
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Transport, as: TransportServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.SpatialGrid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.Loader.Transport, as: TransportLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  def nearby_players(entity, range \\ 250) do
    case entity_position(entity, Time.now()) do
      {world, x, y, z} -> nearby_units_exact(:players, world, {x, y, z}, range)
      nil -> []
    end
  end

  def nearby_mobs(%{object: %{guid: self_guid}} = entity, range \\ 30) do
    nearby(entity, :mobs, range)
    |> Enum.reject(fn {guid, _distance} -> guid == self_guid end)
  end

  def nearby_mobs_at(world, {x, y, z}, range \\ 30) do
    nearby_units_exact(:mobs, world, {x, y, z}, range)
  end

  def nearby_game_objects(%{object: %{guid: self_guid}} = entity, range \\ 30) do
    nearby(entity, :game_objects, range)
    |> Enum.reject(fn {guid, _distance} -> guid == self_guid end)
  end

  def setup_spatial_index, do: SpatialHash.setup_tables()

  def nearby_units_exact(table, world, {x, y, z} = origin, range, now \\ Time.now()) do
    world = WorldRef.coerce(world)

    SpatialHash.query_cells(table, world, x, y, z, range + SpatialGrid.max_cell_drift())
    |> Enum.flat_map(fn guid ->
      case position(guid, now) do
        {^world, tx, ty, tz} ->
          distance = Math.distance(origin, {tx, ty, tz})
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if distance <= range, do: [{guid, distance}], else: []

        _ ->
          []
      end
    end)
  end

  def nearby_players_at(world, {x, y, z}, range \\ 30) do
    nearby_units_exact(:players, world, {x, y, z}, range)
  end

  def players_near?(world, {x, y, z}, range) do
    nearby_players_at(world, {x, y, z}, range) != []
  end

  def player_cell_memberships do
    :players
    |> SpatialHash.cells()
    |> Enum.flat_map(&SpatialHash.entities(:players, &1))
  end

  def cell_for(guid, now \\ Time.now()) when is_integer(guid) and is_integer(now) do
    case position(guid, now) do
      {world, x, y, z} -> SpatialGrid.cell(world, x, y, z)
      nil -> nil
    end
  end

  def update_position(%Character{} = entity), do: Presence.relocate(entity)
  def update_position(%Mob{} = entity), do: update_position(entity, :mobs)
  def update_position(%GameObject{} = entity), do: update_position(entity, :game_objects)
  def update_position(%Corpse{} = entity), do: update_position(entity, :corpses)
  def update_position(%DataDynamicObject{} = entity), do: update_position(entity, :dynamic_objects)
  def update_position(_entity), do: :ok

  def update_position(
        %{object: %{guid: _guid}, internal: %Internal{world: _world}, movement_block: %MovementBlock{}} = entity,
        table
      ) do
    Position.put(entity, table)
  end

  def remove_position(%Character{} = entity), do: Presence.leave(entity)
  def remove_position(%Mob{} = entity), do: remove_position(entity, :mobs)
  def remove_position(%GameObject{} = entity), do: remove_position(entity, :game_objects)
  def remove_position(%Corpse{} = entity), do: remove_position(entity, :corpses)
  def remove_position(%DataDynamicObject{} = entity), do: remove_position(entity, :dynamic_objects)
  def remove_position(_entity), do: :ok

  def remove_position(%{object: %{guid: _guid}} = entity, table), do: Position.remove(entity, table)

  def broadcast_packet(packet, entity, opts \\ [])

  def broadcast_packet(packets, entity, opts) when is_list(packets) do
    Enum.each(packets, fn packet -> broadcast_packet(packet, entity, opts) end)
  end

  def broadcast_packet(packet, entity, opts) do
    include_self? = Keyword.get(opts, :include_self?, true)
    source_guid = entity_guid(entity)

    opts
    |> broadcast_recipients(entity, Keyword.get(opts, :range))
    |> Enum.each(fn guid ->
      if include_self? or guid != source_guid do
        send_broadcast_packet(packet, guid, source_guid)
      end
    end)
  end

  defp send_broadcast_packet(packet, source_guid, source_guid) do
    Network.send_packet(packet, source_guid)
  end

  defp send_broadcast_packet(packet, guid, source_guid) do
    Network.send_packet(packet, guid, source_guid: source_guid)
  end

  def tracking_players(entity) do
    case entity_position(entity, Time.now()) do
      {world, x, y, z} -> SpatialHash.query_cells(:players, world, x, y, z, 250)
      nil -> []
    end
  end

  def start_entity(%GameObject{} = entity) do
    case transport_route(entity) do
      nil -> start_entity(entity, GameObjectServer)
      route -> start_entity(entity, TransportServer, {entity, route})
    end
  end

  def start_entity(%Mob{} = entity), do: start_entity(entity, MobServer)
  def start_entity(%Corpse{} = entity), do: start_entity(entity, CorpseServer)

  def start_entity(%{entity: %DataDynamicObject{object: %{guid: guid}}} = opts) do
    case SpatialHash.get_entity(guid) do
      nil -> EntitySupervisor.start_child(guid, {DynamicObjectServer, opts})
      _ -> :ok
    end
  end

  def start_entity(entity, server), do: start_entity(entity, server, entity)

  defp start_entity(entity, server, argument) do
    # TODO needed to prevent dupes, but maybe a registry is better
    case SpatialHash.get_entity(entity.object.guid) do
      nil -> EntitySupervisor.start_child(entity.object.guid, {server, argument})
      _ -> :ok
    end
  end

  def start_incarnation(%GameObject{} = entity) do
    case transport_route(entity) do
      nil -> start_incarnation(entity, GameObjectServer, entity)
      route -> start_incarnation(entity, TransportServer, {entity, route})
    end
  end

  def start_incarnation(%Mob{} = entity), do: start_incarnation(entity, MobServer)

  defp start_incarnation(entity, server), do: start_incarnation(entity, server, entity)

  defp start_incarnation(entity, server, argument) do
    case Entity.pid(entity.object.guid) do
      nil ->
        child_spec = Supervisor.child_spec({server, argument}, restart: :temporary)
        EntitySupervisor.start_child(entity.object.guid, child_spec)

      pid when is_pid(pid) ->
        {:error, {:already_started, pid}}
    end
  end

  defp transport_route(%GameObject{} = entity) do
    if GameObject.transport?(entity), do: TransportLoader.get(entity.object.entry)
  end

  defp global_transport?(guid, %WorldRef{} = world) do
    Guid.transport?(guid) and WorldRef.open?(world)
  end

  def stop_entity(pid) when is_pid(pid) do
    EntitySupervisor.terminate_child(pid)
  end

  def stop_entity(guid) when is_integer(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> EntitySupervisor.terminate_child(pid)
      _ -> :ok
    end
  end

  def stop_world_entities(%WorldRef{} = world, opts \\ []) do
    excluded = [:player | Keyword.get(opts, :except, [])]

    world
    |> SpatialHash.guids()
    |> Enum.reject(&(Guid.entity_type(&1) in excluded or global_transport?(&1, world)))
    |> Enum.each(&stop_entity/1)
  end

  def guids(%WorldRef{} = world), do: SpatialHash.guids(world)

  def target_position(guid) when is_integer(guid) do
    position(guid)
  end

  def grounded_target_position(guid, now \\ Time.now()) when is_integer(guid) and is_integer(now) do
    guid |> position(now) |> ground_if_airborne(guid)
  end

  defp ground_if_airborne({%WorldRef{map_id: map_id} = world, x, y, z} = position, guid) do
    if airborne?(guid) do
      {gx, gy, gz} = Pathfinding.snap_to_ground(map_id, {x, y, z})
      {world, gx, gy, gz}
    else
      position
    end
  end

  defp ground_if_airborne(position, _guid), do: position

  defp airborne?(guid) do
    case Metadata.query(guid, [:airborne?]) do
      %{airborne?: true} -> true
      _ -> false
    end
  end

  def moving?(guid, now \\ Time.now()) when is_integer(guid) and is_integer(now) do
    spline_moving?(guid, now) or recently_moved?(guid, now)
  end

  defp spline_moving?(guid, now), do: Position.moving?(guid, now)

  defp recently_moved?(guid, now) do
    case Metadata.query(guid, [:moving_until]) do
      %{moving_until: moving_until} when is_integer(moving_until) -> now < moving_until
      _ -> false
    end
  end

  def position(guid, now \\ Time.now()) when is_integer(guid), do: Position.get(guid, now)

  def projected_position(guid, horizon_ms, now \\ Time.now())
      when is_integer(guid) and is_integer(horizon_ms) and horizon_ms >= 0 and is_integer(now) do
    position = grounded_target_position(guid, now)
    project_position(position, Metadata.query(guid, [:movement_velocity, :moving_until]), horizon_ms, now)
  end

  defp project_position({map, x, y, z}, %{movement_velocity: {vx, vy, vz}, moving_until: moving_until}, horizon_ms, now)
       when is_number(vx) and is_number(vy) and is_number(vz) and is_integer(moving_until) and moving_until > now do
    seconds = horizon_ms / 1_000
    {map, x + vx * seconds, y + vy * seconds, z + vz * seconds}
  end

  defp project_position(position, _metadata, _horizon_ms, _now), do: position

  def distance_between(source, target, now \\ Time.now())

  def distance_between(%{internal: %Internal{}, movement_block: %MovementBlock{}} = source, guid, now)
      when is_integer(guid) and is_integer(now) do
    case {entity_position(source, now), position(guid, now)} do
      {{world, x1, y1, z1}, {world, x2, y2, z2}} -> Math.distance({x1, y1, z1}, {x2, y2, z2})
      _ -> nil
    end
  end

  def distance_between(source_guid, target_guid, now)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(now) do
    case {position(source_guid, now), position(target_guid, now)} do
      {{world, x1, y1, z1}, {world, x2, y2, z2}} -> Math.distance({x1, y1, z1}, {x2, y2, z2})
      _ -> nil
    end
  end

  def line_of_sight?(%{internal: %Internal{}, movement_block: %MovementBlock{}} = entity, guid) when is_integer(guid) do
    now = Time.now()

    case {entity_position(entity, now), position(guid, now)} do
      {{world, x1, y1, z1}, {world, x2, y2, z2}} ->
        Pathfinding.line_of_sight?(world.map_id, {x1, y1, z1}, {x2, y2, z2})

      _ ->
        true
    end
  end

  def line_of_sight?(_entity, _guid), do: true

  defp entity_guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  defp entity_guid(%{guid: guid}) when is_integer(guid), do: guid
  defp entity_guid(_entity), do: nil

  defp broadcast_recipients(opts, entity, range) do
    opts
    |> Keyword.get(:recipients)
    |> normalize_recipients(entity, range)
  end

  defp normalize_recipients(recipients, _entity, _range) when is_list(recipients), do: recipients
  defp normalize_recipients(%MapSet{} = recipients, _entity, _range), do: MapSet.to_list(recipients)

  defp normalize_recipients(_recipients, entity, nil), do: tracking_players(entity)

  defp normalize_recipients(_recipients, entity, range) do
    entity
    |> nearby_players(range)
    |> Enum.map(fn {guid, _distance} -> guid end)
  end

  defp nearby(entity, table, range) do
    case entity_position(entity, Time.now()) do
      {world, x, y, z} -> nearby_units_exact(table, world, {x, y, z}, range)
      nil -> []
    end
  end

  defp entity_position(%{internal: %Internal{world: world}, movement_block: %MovementBlock{}} = entity, now) do
    %{movement_block: %MovementBlock{position: {x, y, z, _orientation}}} = Movement.sync_position(entity, now)
    {world, x, y, z}
  end

  defp entity_position(_entity, _now), do: nil
end
