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
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  def nearby_players(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}},
        range \\ 250
      ) do
    SpatialHash.query(:players, map, x, y, z, range)
  end

  def nearby_mobs(
        %{
          object: %{guid: self_guid},
          internal: %Internal{map: map},
          movement_block: %MovementBlock{position: {x, y, z, _o}}
        },
        range \\ 30
      ) do
    nearby_units_exact(:mobs, map, {x, y, z}, range)
    |> Enum.reject(fn {guid, _distance} -> guid == self_guid end)
  end

  def nearby_mobs_at(map, {x, y, z}, range \\ 30) do
    nearby_units_exact(:mobs, map, {x, y, z}, range)
  end

  @position_drift_margin 180.0

  def nearby_units_exact(table, map, {x, y, z} = origin, range, now \\ Time.now()) do
    SpatialHash.query(table, map, x, y, z, range + @position_drift_margin)
    |> Enum.flat_map(fn {guid, _stale_distance} ->
      case position(guid, now) do
        {^map, tx, ty, tz} ->
          distance = SpatialHash.distance(origin, {tx, ty, tz})
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if distance <= range, do: [{guid, distance}], else: []

        _ ->
          []
      end
    end)
  end

  def nearby_players_at(map, {x, y, z}, range \\ 30) do
    SpatialHash.query(:players, map, x, y, z, range)
  end

  def update_position(%Character{} = entity), do: update_position(entity, :players)
  def update_position(%Mob{} = entity), do: update_position(entity, :mobs)
  def update_position(%GameObject{} = entity), do: update_position(entity, :game_objects)
  def update_position(%Corpse{} = entity), do: update_position(entity, :corpses)
  def update_position(%DataDynamicObject{} = entity), do: update_position(entity, :dynamic_objects)
  def update_position(_entity), do: :ok

  def update_position(
        %{
          object: %{guid: guid},
          internal: %Internal{map: map},
          movement_block: %MovementBlock{position: {x, y, z, _o}, spline_nodes: spline_nodes}
        },
        table
      ) do
    if spline_nodes in [nil, []], do: SpatialHash.clear_movement(guid)
    SpatialHash.update(table, guid, map, x, y, z)
  end

  def remove_position(%Character{} = entity), do: remove_position(entity, :players)
  def remove_position(%Mob{} = entity), do: remove_position(entity, :mobs)
  def remove_position(%GameObject{} = entity), do: remove_position(entity, :game_objects)
  def remove_position(%Corpse{} = entity), do: remove_position(entity, :corpses)
  def remove_position(%DataDynamicObject{} = entity), do: remove_position(entity, :dynamic_objects)
  def remove_position(_entity), do: :ok

  def remove_position(%{object: %{guid: guid}}, table) do
    SpatialHash.remove(table, guid)
  end

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
        Network.send_packet(packet, guid, source_guid: source_guid)
      end
    end)
  end

  def tracking_players(%{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    SpatialHash.query_cells(:players, map, x, y, z, 250)
  end

  def start_entity(%GameObject{} = entity), do: start_entity(entity, GameObjectServer)
  def start_entity(%Mob{} = entity), do: start_entity(entity, MobServer)
  def start_entity(%Corpse{} = entity), do: start_entity(entity, CorpseServer)

  def start_entity(%{entity: %DataDynamicObject{object: %{guid: guid}}} = opts) do
    case SpatialHash.get_entity(guid) do
      nil -> DynamicSupervisor.start_child(EntitySupervisor, {DynamicObjectServer, opts})
      _ -> :ok
    end
  end

  def start_entity(entity, server) do
    # TODO needed to prevent dupes, but maybe a registry is better
    case SpatialHash.get_entity(entity.object.guid) do
      nil -> DynamicSupervisor.start_child(EntitySupervisor, {server, entity})
      _ -> :ok
    end
  end

  def stop_entity(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(EntitySupervisor, pid)
  end

  def stop_entity(guid) when is_integer(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> DynamicSupervisor.terminate_child(EntitySupervisor, pid)
      _ -> :ok
    end
  end

  def target_position(guid) when is_integer(guid) do
    position(guid)
  end

  def moving?(guid, now \\ Time.now()) when is_integer(guid) and is_integer(now) do
    spline_moving?(guid, now) or recently_moved?(guid, now)
  end

  defp spline_moving?(guid, now) do
    case SpatialHash.get_movement(guid) do
      {_map, _start_position, spline_nodes, start_time, duration}
      when is_list(spline_nodes) and spline_nodes != [] and is_integer(start_time) and is_integer(duration) and
             duration > 0 ->
        now <= start_time + duration

      _ ->
        false
    end
  end

  defp recently_moved?(guid, now) do
    case Metadata.query(guid, [:moving_until]) do
      %{moving_until: moving_until} when is_integer(moving_until) -> now < moving_until
      _ -> false
    end
  end

  def position(guid, now \\ Time.now()) when is_integer(guid) do
    case SpatialHash.get_movement(guid) do
      {map, start_position, spline_nodes, start_time, duration} ->
        {x, y, z} = Movement.position_at(start_position, spline_nodes, duration, now - start_time)
        {map, x, y, z}

      nil ->
        case SpatialHash.get_entity(guid) do
          {^guid, map, x, y, z} -> {map, x, y, z}
          nil -> nil
        end
    end
  end

  def publish_movement(%{
        object: %{guid: guid},
        internal: %Internal{map: map, movement_start_time: start_time, movement_start_position: start_position},
        movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
      })
      when is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and
             is_integer(duration) and duration > 0 do
    SpatialHash.put_movement(guid, {map, start_position, spline_nodes, start_time, duration})
  end

  def publish_movement(_entity), do: :ok

  def clear_movement(%{object: %{guid: guid}}) when is_integer(guid) do
    SpatialHash.clear_movement(guid)
  end

  def clear_movement(_entity), do: :ok

  def distance_to_guid(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x1, y1, z1, _o}}},
        guid
      )
      when is_integer(guid) do
    case target_position(guid) do
      {^map, x2, y2, z2} -> SpatialHash.distance({x1, y1, z1}, {x2, y2, z2})
      _ -> nil
    end
  end

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
end
